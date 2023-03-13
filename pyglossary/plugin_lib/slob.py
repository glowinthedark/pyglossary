# pylint: disable=C0111,C0103,C0302,R0903,R0904,R0914,R0201
import encodings
import io
import os
import pickle
import sys
import tempfile
import typing
import warnings
from abc import abstractmethod
from bisect import bisect_left
from builtins import open as fopen
from collections import namedtuple
from datetime import datetime, timezone
from functools import lru_cache
from os.path import isdir
from struct import calcsize, pack, unpack
from threading import RLock
from types import MappingProxyType
from typing import (
	Any,
	Callable,
	Generic,
	Iterator,
	Sequence,
	TypeVar,
	Union,
	cast,
)
from uuid import UUID, uuid4

import icu
from icu import Collator, Locale, UCollAttribute, UCollAttributeValue

DEFAULT_COMPRESSION = 'lzma2'

UTF8 = 'utf-8'
MAGIC = b'!-1SLOB\x1F'

Compression = namedtuple('Compression', 'compress decompress')

Ref = namedtuple(
	'Ref',
	['key', 'bin_index', 'item_index', 'fragment'],
)

Header = namedtuple(
	'Header',
	'magic uuid encoding '
	'compression tags content_types '
	'blob_count '
	'store_offset '
	'refs_offset '
	'size',
)

U_CHAR = '>B'
U_CHAR_SIZE = calcsize(U_CHAR)
U_SHORT = '>H'
U_SHORT_SIZE = calcsize(U_SHORT)
U_INT = '>I'
U_INT_SIZE = calcsize(U_INT)
U_LONG_LONG = '>Q'
U_LONG_LONG_SIZE = calcsize(U_LONG_LONG)


def calcmax(len_size_spec):
	return 2 ** (calcsize(len_size_spec) * 8) - 1


MAX_TEXT_LEN = calcmax(U_SHORT)
MAX_TINY_TEXT_LEN = calcmax(U_CHAR)
MAX_LARGE_BYTE_STRING_LEN = calcmax(U_INT)
MAX_BIN_ITEM_COUNT = calcmax(U_SHORT)


PRIMARY = Collator.PRIMARY
SECONDARY = Collator.SECONDARY
TERTIARY = Collator.TERTIARY
QUATERNARY = Collator.QUATERNARY
IDENTICAL = Collator.IDENTICAL


def init_compressions():
	def ident(x):
		return x

	compressions = {'': Compression(ident, ident)}
	for name in ('bz2', 'zlib'):
		try:
			m = __import__(name)
		except ImportError:
			warnings.warning(f'{name} is not available')
			continue

		def compress_new(x, m=m):
			return m.compress(x, 9)

		compressions[name] = Compression(compress_new, m.decompress)

	try:
		import lzma
	except ImportError:
		warnings.warn('lzma is not available')
	else:
		filters = [{'id': lzma.FILTER_LZMA2}]
		compressions['lzma2'] = Compression(
			lambda s: lzma.compress(
				s,
				format=lzma.FORMAT_RAW,
				filters=filters,
			),
			lambda s: lzma.decompress(
				s,
				format=lzma.FORMAT_RAW,
				filters=filters,
			),
		)
	return compressions


COMPRESSIONS = init_compressions()


del init_compressions


MIME_TEXT = 'text/plain'
MIME_HTML = 'text/html'
MIME_CSS = 'text/css'
MIME_JS = 'application/javascript'

MIME_TYPES = {
	"html": MIME_HTML,
	"txt": MIME_TEXT,
	"js": MIME_JS,
	"css": MIME_CSS,
	"json": "application/json",
	"woff": "application/font-woff",
	"svg": "image/svg+xml",
	"png": "image/png",
	"jpg": "image/jpeg",
	"jpeg": "image/jpeg",
	"gif": "image/gif",
	"ttf": "application/x-font-ttf",
	"otf": "application/x-font-opentype",
}


class FileFormatException(Exception):
	pass


class UnknownFileFormat(FileFormatException):
	pass


class UnknownCompression(FileFormatException):
	pass


class UnknownEncoding(FileFormatException):
	pass


class IncorrectFileSize(FileFormatException):
	pass


class TagNotFound(Exception):
	pass


@lru_cache(maxsize=None)
def sortkey(
	strength: int,
	maxlength: "int | None" = None,
) -> "Callable":
	c = Collator.createInstance(Locale())
	c.setStrength(strength)
	c.setAttribute(
		UCollAttribute.ALTERNATE_HANDLING,
		UCollAttributeValue.SHIFTED,
	)
	if maxlength is None:
		return c.getSortKey
	return lambda x: c.getSortKey(x)[:maxlength]


class MultiFileReader(io.BufferedIOBase):
	def __init__(
		self: "typing.Self",
		*args: str,
	) -> None:
		filenames: "list[str]" = list(args)
		files = []
		ranges = []
		offset = 0
		for name in filenames:
			size = os.stat(name).st_size
			ranges.append(range(offset, offset + size))
			files.append(fopen(name, 'rb'))
			offset += size
		self.size = offset
		self._ranges = ranges
		self._files = files
		self._fcount = len(self._files)
		self._offset = -1
		self.seek(0)

	def __enter__(self: "typing.Self") -> "MultiFileReader":
		return self

	def __exit__(self: "typing.Self", exc_type, exc_val, exc_tb):
		self.close()
		return False

	def close(self: "typing.Self") -> None:
		for f in self._files:
			f.close()
		self._files.clear()
		self._ranges.clear()

	@property
	def closed(self: "typing.Self") -> bool:
		return len(self._ranges) == 0

	def isatty(self: "typing.Self") -> bool:
		return False

	def readable(self: "typing.Self") -> bool:
		return True

	def seek(self: "typing.Self", offset, whence=io.SEEK_SET):
		if whence == io.SEEK_SET:
			self._offset = offset
		elif whence == io.SEEK_CUR:
			self._offset = self._offset + offset
		elif whence == io.SEEK_END:
			self._offset = self.size + offset
		else:
			raise ValueError('Invalid value for parameter whence: %r' % whence)
		return self._offset

	def seekable(self: "typing.Self"):
		return True

	def tell(self: "typing.Self"):
		return self._offset

	def writable(self: "typing.Self"):
		return False

	def read(self: "typing.Self", n=-1):
		file_index = -1
		actual_offset = 0
		for i, r in enumerate(self._ranges):
			if self._offset in r:
				file_index = i
				actual_offset = self._offset - r.start
				break
		result = b''
		if (n == -1 or n is None):
			to_read = self.size
		else:
			to_read = n
		while -1 < file_index < self._fcount:
			f = self._files[file_index]
			f.seek(actual_offset)
			read = f.read(to_read)
			read_count = len(read)
			self._offset += read_count
			result += read
			to_read -= read_count
			if to_read > 0:
				file_index += 1
				actual_offset = 0
			else:
				break
		return result


class KeydItemDict(object):
	def __init__(
		self: "typing.Self",
		blobs: "Sequence[Blob | Ref]",
		strength: int,
		maxlength: "int | None" = None,
	) -> None:
		self.blobs = blobs
		self.sortkey = sortkey(strength, maxlength=maxlength)

	def __len__(self: "typing.Self") -> int:
		return len(self.blobs)

	def __getitem__(self: "typing.Self", key: str) -> "Iterator[Blob | Ref]":
		blobs = self.blobs
		key_as_sk = self.sortkey(key)
		i = bisect_left(
			blobs,
			key_as_sk,
			key=lambda blob: self.sortkey(blob.key),
		)
		if i == len(blobs):
			return
		while i < len(blobs):
			if self.sortkey(blobs[i].key) == key_as_sk:
				yield blobs[i]
			else:
				break
			i += 1
		return

	def __contains__(self: "typing.Self", key: str) -> bool:
		try:
			next(self[key])
		except StopIteration:
			return False
		return True


class Blob(object):
	def __init__(
		self: "typing.Self",
		content_id: int,
		key: str,
		fragment: str,
		read_content_type_func: "Callable[[], str]",
		read_func: "Callable",
	):
		# print(f"read_func is {type(read_func)}")
		# read_func is <class 'functools._lru_cache_wrapper'>
		self._content_id = content_id
		self._key = key
		self._fragment = fragment
		self._read_content_type = read_content_type_func
		self._read = read_func

	@property
	def id(self: "typing.Self"):
		return self._content_id

	@property
	def key(self: "typing.Self"):
		return self._key

	@property
	def fragment(self: "typing.Self"):
		return self._fragment

	@property
	def content_type(self: "typing.Self"):
		return self._read_content_type()

	@property
	def content(self: "typing.Self"):
		return self._read()

	def __str__(self: "typing.Self") -> str:
		return self.key

	def __repr__(self: "typing.Self"):
		return f'<{self.__class__.__module__}.{self.__class__.__name__} {self.key}>'


def read_byte_string(f, len_spec):
	length = unpack(len_spec, f.read(calcsize(len_spec)))[0]
	return f.read(length)


class StructReader():
	def __init__(
		self: "typing.Self",
		_file: "io.IOBase",
		encoding=None,	
	) -> None:
		self._file = _file
		self.encoding = encoding

	def read_int(self: "typing.Self"):
		s = self.read(U_INT_SIZE)
		return unpack(U_INT, s)[0]

	def read_long(self: "typing.Self"):
		b = self.read(U_LONG_LONG_SIZE)
		return unpack(U_LONG_LONG, b)[0]

	def read_byte(self: "typing.Self"):
		s = self.read(U_CHAR_SIZE)
		return unpack(U_CHAR, s)[0]

	def read_short(self: "typing.Self"):
		return unpack(U_SHORT, self._file.read(U_SHORT_SIZE))[0]

	def _read_text(self: "typing.Self", len_spec):
		max_len = 2 ** (8 * calcsize(len_spec)) - 1
		byte_string = read_byte_string(self._file, len_spec)
		if len(byte_string) == max_len:
			terminator = byte_string.find(0)
			if terminator > -1:
				byte_string = byte_string[:terminator]
		return byte_string.decode(self.encoding)

	def read_tiny_text(self: "typing.Self"):
		return self._read_text(U_CHAR)

	def read_text(self: "typing.Self"):
		return self._read_text(U_SHORT)

	def read(self, n: int) -> bytes:
		return self._file.read(n)

	def write(self, data: bytes) -> int:
		return self._file.write(data)

	def seek(self, pos: int) -> None:
		self._file.seek(pos)

	def tell(self) -> int:
		return self._file.tell()



class StructWriter:

	def __init__(self: "typing.Self", _file, encoding=None) -> None:
		self._file = _file
		self.encoding = encoding

	def write_int(self: "typing.Self", value):
		self._file.write(pack(U_INT, value))

	def write_long(self: "typing.Self", value):
		self._file.write(pack(U_LONG_LONG, value))

	def write_byte(self: "typing.Self", value):
		self._file.write(pack(U_CHAR, value))

	def write_short(self: "typing.Self", value):
		self._file.write(pack(U_SHORT, value))

	def _write_text(
		self: "typing.Self",
		text,
		len_size_spec,
		encoding=None,
		pad_to_length=None,
	):
		if encoding is None:
			encoding = self.encoding
		text_bytes = text.encode(encoding)
		length = len(text_bytes)
		max_length = calcmax(len_size_spec)
		if length > max_length:
			raise ValueError("Text is too long for size spec %s" % len_size_spec)
		self._file.write(pack(
			len_size_spec,
			pad_to_length if pad_to_length else length,
		))
		self._file.write(text_bytes)
		if pad_to_length:
			for _ in range(pad_to_length - length):
				self._file.write(pack(U_CHAR, 0))

	def write_tiny_text(self: "typing.Self", text, encoding=None, editable=False):
		pad_to_length = 255 if editable else None
		self._write_text(
			text,
			U_CHAR,
			encoding=encoding,
			pad_to_length=pad_to_length,
		)

	def write_text(self: "typing.Self", text, encoding=None):
		self._write_text(text, U_SHORT, encoding=encoding)

	def __getattr__(self: "typing.Self", name):
		return getattr(self._file, name)


def set_tag_value(filename, name, value):
	with fopen(filename, 'rb+') as _file:
		_file.seek(len(MAGIC) + 16)
		encoding = read_byte_string(_file, U_CHAR).decode(UTF8)
		if encodings.search_function(encoding) is None:
			raise UnknownEncoding(encoding)
		reader = StructWriter(
			StructReader(_file, encoding=encoding),
			encoding=encoding,
		)
		reader.read_tiny_text()
		tag_count = reader.read_byte()
		for _ in range(tag_count):
			key = reader.read_tiny_text()
			if key == name:
				reader.write_tiny_text(value, editable=True)
				return
			reader.read_tiny_text()
	raise TagNotFound(name)


def read_header(f):
	f.seek(0)

	magic = f.read(len(MAGIC))
	if (magic != MAGIC):
		raise UnknownFileFormat(f"magic {magic!r} != {MAGIC!r}")

	uuid = UUID(bytes=f.read(16))
	encoding = read_byte_string(f, U_CHAR).decode(UTF8)
	if encodings.search_function(encoding) is None:
		raise UnknownEncoding(encoding)

	f = StructReader(f, encoding)
	compression = f.read_tiny_text()
	if compression not in COMPRESSIONS:
		raise UnknownCompression(compression)

	def read_tags():
		tags = {}
		count = f.read_byte()
		for _ in range(count):
			key = f.read_tiny_text()
			value = f.read_tiny_text()
			tags[key] = value
		return tags
	tags = read_tags()

	def read_content_types() -> "Sequence[str]":
		content_types: "list[str]" = []
		count = f.read_byte()
		for _ in range(count):
			content_type = f.read_text()
			content_types.append(content_type)
		return tuple(content_types)

	content_types = read_content_types()

	blob_count = f.read_int()
	store_offset = f.read_long()
	size = f.read_long()
	refs_offset = f.tell()

	return Header(
		magic=magic,
		uuid=uuid,
		encoding=encoding,
		compression=compression,
		tags=MappingProxyType(tags),
		content_types=content_types,
		blob_count=blob_count,
		store_offset=store_offset,
		refs_offset=refs_offset,
		size=size,
	)


def meld_ints(a, b):
	return (a << 16) | b


def unmeld_ints(c):
	bstr = bin(c).lstrip("0b").zfill(48)
	a, b = bstr[-48:-16], bstr[-16:]
	return int(a, 2), int(b, 2)


class Slob(object):
	def __init__(self: "typing.Self", *filenames) -> None:
		self._f = MultiFileReader(*filenames)

		try:
			self._header = read_header(self._f)
			if (self._f.size != self._header.size):
				raise IncorrectFileSize(
					'File size should be {0}, {1} bytes found'
					.format(self._header.size, self._f.size))
		except FileFormatException:
			self._f.close()
			raise

		self._refs = RefList(
			self._f,
			self._header.encoding,
			offset=self._header.refs_offset,
		)

		self._g = MultiFileReader(*filenames)
		self._store = Store(
			self._g,
			self._header.store_offset,
			COMPRESSIONS[self._header.compression].decompress,
			self._header.content_types,
		)

	def __enter__(self: "typing.Self"):
		return self

	def __exit__(self: "typing.Self", exc_type, exc_val, exc_tb):
		self.close()
		return False

	@property
	def id(self: "typing.Self"):
		return self._header.uuid.hex

	@property
	def content_types(self: "typing.Self"):
		return self._header.content_types

	@property
	def tags(self: "typing.Self"):
		return self._header.tags

	@property
	def blob_count(self: "typing.Self"):
		return self._header.blob_count

	@property
	def compression(self: "typing.Self"):
		return self._header.compression

	@property
	def encoding(self: "typing.Self"):
		return self._header.encoding

	def __len__(self: "typing.Self"):
		return len(self._refs)

	def __getitem__(self: "typing.Self", i: int) -> "Any":
		# this is called by bisect_left
		return self.getBlobByIndex(i)

	def __iter__(self) -> "Iterator[Blob]":
		for i in range(len(self._refs)):
			yield self.getBlobByIndex(i)

	def count(self) -> int:
		# just to comply with Sequence and make type checker happy
		raise NotImplementedError

	def index(self, x: Any) -> int:
		# just to comply with Sequence and make type checker happy
		raise NotImplementedError

	def getBlobByIndex(self: "typing.Self", i: int) -> "Blob":
		ref = self._refs[i]

		def read_func():
			return self._store.get(ref.bin_index, ref.item_index)[1]
		read_func = lru_cache(maxsize=None)(read_func)

		def read_content_type_func() -> str:
			return self._store.content_type(ref.bin_index, ref.item_index)

		content_id = meld_ints(ref.bin_index, ref.item_index)
		return Blob(
			content_id=content_id,
			key=ref.key,
			fragment=ref.fragment,
			read_content_type_func=read_content_type_func,
			read_func=read_func,
		)

	def get(self: "typing.Self", blob_id) -> "Blob":
		bin_index, bin_item_index = unmeld_ints(blob_id)
		return self._store.get(bin_index, bin_item_index)

	@lru_cache(maxsize=None)  # noqa: B019
	def as_dict(
		self: "Slob",
		strength=TERTIARY,
		maxlength=None,
	):
		return KeydItemDict(
			cast(Sequence, self),
			strength=strength,
			maxlength=maxlength,
		)

	def close(self: "typing.Self"):
		self._f.close()
		self._g.close()


def find_parts(fname):
	fname = os.path.expanduser(fname)
	dirname = os.path.dirname(fname) or os.getcwd()
	basename = os.path.basename(fname)
	candidates = []
	for name in os.listdir(dirname):
		if name.startswith(basename):
			candidates.append(os.path.join(dirname, name))
	return sorted(candidates)


def open(*filenames):
	return Slob(*filenames)


class BinMemWriter:

	def __init__(self: "typing.Self") -> None:
		self.content_type_ids: "list[str]" = []
		self.item_dir: "list[bytes]" = []
		self.items: "list[bytes]" = []
		self.current_offset = 0

	def add(self: "typing.Self", content_type_id, blob):
		self.content_type_ids.append(content_type_id)
		self.item_dir.append(pack(U_INT, self.current_offset))
		length_and_bytes = pack(U_INT, len(blob)) + blob
		self.items.append(length_and_bytes)
		self.current_offset += len(length_and_bytes)

	def __len__(self: "typing.Self"):
		return len(self.item_dir)

	def finalize(
		self: "typing.Self",
		fout: "io.BufferedIOBase",
		compress: "Callable[[bytes], bytes]",
	):
		count = len(self)
		fout.write(pack(U_INT, count))
		for content_type_id in self.content_type_ids:
			fout.write(pack(U_CHAR, content_type_id))
		content = b''.join(self.item_dir + self.items)
		compressed = compress(content)
		fout.write(pack(U_INT, len(compressed)))
		fout.write(compressed)
		self.content_type_ids.clear()
		self.item_dir.clear()
		self.items.clear()


ItemT = TypeVar("ItemT")

class ItemList(Generic[ItemT]):
	def __init__(
		self: "typing.Self",
		reader: "StructReader",
		offset: int,
		count_or_spec: "Union[str, int]",
		pos_spec: str,
	):
		self.lock = RLock()
		self.reader = reader
		reader.seek(offset)
		count: int
		if isinstance(count_or_spec, str):
			count_spec = count_or_spec
			count = unpack(count_spec, reader.read(calcsize(count_spec)))[0]
		elif isinstance(count_or_spec, int):
			count = count_or_spec
		else:
			raise TypeError("invalid {count_or_spec = }")
		self._count: int = count
		self.pos_offset = reader.tell()
		self.pos_spec = pos_spec
		self.pos_size = calcsize(pos_spec)
		self.data_offset = self.pos_offset + self.pos_size * count

	def __len__(self: "typing.Self") -> int:
		return self._count

	def pos(self: "typing.Self", i):
		with self.lock:
			self.reader.seek(self.pos_offset + self.pos_size * i)
			return unpack(self.pos_spec, self.reader.read(self.pos_size))[0]

	def read(self: "typing.Self", pos: int) -> ItemT:
		with self.lock:
			self.reader.seek(self.data_offset + pos)
			return self._read_item()

	@abstractmethod
	def _read_item(self: "typing.Self") -> ItemT:
		pass

	def __getitem__(self: "typing.Self", i: int) -> ItemT:
		if i >= len(self) or i < 0:
			raise IndexError('index out of range')
		return self.read(self.pos(i))


class RefList(ItemList[Ref]):
	def __init__(self: "typing.Self", f, encoding, offset=0, count=None) -> None:
		super().__init__(
			reader=StructReader(f, encoding),
			offset=offset,
			count_or_spec=U_INT if count is None else count,
			pos_spec=U_LONG_LONG,
		)

	@lru_cache(maxsize=512)  # noqa: B019
	def __getitem__(
		self: "typing.Self",
		i: int,
	) -> "Ref":
		if i >= len(self) or i < 0:
			raise IndexError('index out of range')
		return cast(Ref, self.read(self.pos(i)))

	def _read_item(self: "typing.Self") -> "Ref":
		key = self.reader.read_text()
		bin_index = self.reader.read_int()
		item_index = self.reader.read_short()
		fragment = self.reader.read_tiny_text()
		return Ref(
			key=key,
			bin_index=bin_index,
			item_index=item_index,
			fragment=fragment,
		)

	@lru_cache(maxsize=None)  # noqa: B019
	def as_dict(
		self: "RefList",
		strength=TERTIARY,
		maxlength=None,
	) -> KeydItemDict:
		return KeydItemDict(
			cast(Sequence, self),
			strength=strength,
			maxlength=maxlength,
		)


class Bin(ItemList[bytes]):
	def __init__(
		self: "typing.Self",
		count: int,
		bin_bytes: bytes,
	) -> None:
		super().__init__(
			reader=StructReader(io.BytesIO(bin_bytes)),
			offset=0,
			count_or_spec=count,
			pos_spec=U_INT,
		)

	def _read_item(self: "typing.Self") -> bytes:
		content_len = self.reader.read_int()
		return self.reader.read(content_len)


StoreItem = namedtuple('StoreItem', 'content_type_ids compressed_content')


class Store(ItemList[StoreItem]):
	def __init__(
		self: "typing.Self",
		_file,
		offset,
		decompress,
		content_types,
	) -> None:
		super().__init__(
			reader=StructReader(_file),
			offset=offset,
			count_or_spec=U_INT,
			pos_spec=U_LONG_LONG,
		)
		self.decompress = decompress
		self.content_types = content_types

	@lru_cache(maxsize=32)  # noqa: B019
	def __getitem__(
		self: "typing.Self",
		i: int,
	) -> "StoreItem":
		if i >= len(self) or i < 0:
			raise IndexError('index out of range')
		return cast(StoreItem, self.read(self.pos(i)))

	def _read_item(self: "typing.Self") -> "StoreItem":
		bin_item_count = self.reader.read_int()
		packed_content_type_ids = self.reader.read(bin_item_count * U_CHAR_SIZE)
		content_type_ids = []
		for i in range(bin_item_count):
			content_type_id = unpack(U_CHAR, packed_content_type_ids[i:i + 1])[0]
			content_type_ids.append(content_type_id)
		content_length = self.reader.read_int()
		content = self.reader.read(content_length)
		return StoreItem(
			content_type_ids=content_type_ids,
			compressed_content=content,
		)

	def _content_type(
		self: "typing.Self",
		bin_index: int,
		item_index: int,
	) -> "tuple[str, StoreItem]":
		store_item = self[bin_index]
		content_type_id = store_item.content_type_ids[item_index]
		content_type = self.content_types[content_type_id]
		return content_type, store_item

	def content_type(
		self: "typing.Self",
		bin_index: int,
		item_index: int,
	) -> str:
		return self._content_type(bin_index, item_index)[0]

	@lru_cache(maxsize=16)  # noqa: B019
	def _decompress(self: "typing.Self", bin_index):
		store_item = self[bin_index]
		return self.decompress(store_item.compressed_content)

	def get(self: "typing.Self", bin_index, item_index):
		content_type, store_item = self._content_type(bin_index, item_index)
		content = self._decompress(bin_index)
		count = len(store_item.content_type_ids)
		store_bin = Bin(count, content)
		content = store_bin[item_index]
		return (content_type, content)


WriterEvent = namedtuple('WriterEvent', 'name data')


class KeyTooLongException(Exception):

	@property
	def key(self: "typing.Self"):
		return self.args[0]


class Writer(object):

	def __init__(
		self: "typing.Self",
		filename,
		workdir=None,
		encoding=UTF8,
		compression=DEFAULT_COMPRESSION,
		min_bin_size=512 * 1024,
		max_redirects=5,
		observer=None,
	):
		self.filename = filename
		self.observer = observer
		if os.path.exists(self.filename):
			raise SystemExit('File %r already exists' % self.filename)

		# make sure we can write
		with fopen(self.filename, 'wb'):
			pass

		self.encoding = encoding

		if encodings.search_function(self.encoding) is None:
			raise UnknownEncoding(self.encoding)

		self.workdir = workdir

		self.tmpdir = tmpdir = tempfile.TemporaryDirectory(
			prefix='{0}-'.format(os.path.basename(filename)),
			dir=workdir,
		)

		self.f_ref_positions = self._wbfopen('ref-positions')
		self.f_store_positions = self._wbfopen('store-positions')
		self.f_refs = self._wbfopen('refs')
		self.f_store = self._wbfopen('store')

		self.max_redirects = max_redirects
		if max_redirects:
			self.aliases_path = os.path.join(tmpdir.name, 'aliases')
			self.f_aliases = Writer(
				self.aliases_path,
				workdir=tmpdir.name,
				max_redirects=0,
				compression=None,
			)

		if compression is None:
			compression = ''
		if compression not in COMPRESSIONS:
			raise UnknownCompression(compression)

		self.compress = COMPRESSIONS[compression].compress

		self.compression = compression
		self.content_types: "dict[str, int]" = {}

		self.min_bin_size = min_bin_size

		self.current_bin: "BinMemWriter | None" = None

		self.blob_count = 0
		self.ref_count = 0
		self.bin_count = 0
		self._tags = {
			'version.python': sys.version.replace('\n', ' '),
			'version.pyicu': icu.VERSION,
			'version.icu': icu.ICU_VERSION,
			'created.at': datetime.now(timezone.utc).isoformat(),
		}
		self.tags = MappingProxyType(self._tags)

	def _wbfopen(self: "typing.Self", name):
		return StructWriter(
			fopen(os.path.join(self.tmpdir.name, name), 'wb'),
			encoding=self.encoding)

	def tag(self: "typing.Self", name, value=''):
		if len(name.encode(self.encoding)) > MAX_TINY_TEXT_LEN:
			self._fire_event('tag_name_too_long', (name, value))
			return

		if len(value.encode(self.encoding)) > MAX_TINY_TEXT_LEN:
			self._fire_event('tag_value_too_long', (name, value))
			value = ''

		self._tags[name] = value

	def _split_key(self: "typing.Self", key):
		if isinstance(key, str):
			actual_key = key
			fragment = ''
		else:
			actual_key, fragment = key
		if len(actual_key) > MAX_TEXT_LEN or len(fragment) > MAX_TINY_TEXT_LEN:
			raise KeyTooLongException(key)
		return actual_key, fragment

	def add(self: "typing.Self", blob, *keys, content_type=''):

		if len(blob) > MAX_LARGE_BYTE_STRING_LEN:
			self._fire_event('content_too_long', blob)
			return

		if len(content_type) > MAX_TEXT_LEN:
			self._fire_event('content_type_too_long', content_type)
			return

		actual_keys = []

		for key in keys:
			try:
				actual_key, fragment = self._split_key(key)
			except KeyTooLongException as e:
				self._fire_event('key_too_long', e.key)
			else:
				actual_keys.append((actual_key, fragment))

		if len(actual_keys) == 0:
			return

		current_bin = self.current_bin

		if current_bin is None:
			current_bin = self.current_bin = BinMemWriter()
			self.bin_count += 1

		if content_type not in self.content_types:
			self.content_types[content_type] = len(self.content_types)

		current_bin.add(self.content_types[content_type], blob)
		self.blob_count += 1
		bin_item_index = len(current_bin) - 1
		bin_index = self.bin_count - 1

		for actual_key, fragment in actual_keys:
			self._write_ref(actual_key, bin_index, bin_item_index, fragment)

		if (
			current_bin.current_offset > self.min_bin_size or
			len(current_bin) == MAX_BIN_ITEM_COUNT
		):
			self._write_current_bin()

	def add_alias(self: "typing.Self", key, target_key):
		if self.max_redirects:
			try:
				self._split_key(key)
			except KeyTooLongException as e:
				self._fire_event('alias_too_long', e.key)
				return
			try:
				self._split_key(target_key)
			except KeyTooLongException as e:
				self._fire_event('alias_target_too_long', e.key)
				return
			self.f_aliases.add(pickle.dumps(target_key), key)
		else:
			raise NotImplementedError()

	def _fire_event(self: "typing.Self", name, data=None):
		if self.observer:
			self.observer(WriterEvent(name, data))

	def _write_current_bin(self: "typing.Self"):
		current_bin = self.current_bin
		if current_bin is None:
			return
		self.f_store_positions.write_long(self.f_store.tell())
		current_bin.finalize(self.f_store, self.compress)
		self.current_bin = None

	def _write_ref(self: "typing.Self", key, bin_index, item_index, fragment=''):
		self.f_ref_positions.write_long(self.f_refs.tell())
		self.f_refs.write_text(key)
		self.f_refs.write_int(bin_index)
		self.f_refs.write_short(item_index)
		self.f_refs.write_tiny_text(fragment)
		self.ref_count += 1

	def _sort(self: "typing.Self"):
		self._fire_event('begin_sort')
		f_ref_positions_sorted = self._wbfopen('ref-positions-sorted')
		self.f_refs.flush()
		self.f_ref_positions.close()
		with MultiFileReader(self.f_ref_positions.name, self.f_refs.name) as f:
			ref_list = RefList(f, self.encoding, count=self.ref_count)
			sortkey_func = sortkey(IDENTICAL)
			for i in sorted(
				range(len(ref_list)),
				key=lambda j: sortkey_func(ref_list[j].key),
			):
				ref_pos = ref_list.pos(i)
				f_ref_positions_sorted.write_long(ref_pos)
		f_ref_positions_sorted.close()
		os.remove(self.f_ref_positions.name)
		os.rename(f_ref_positions_sorted.name, self.f_ref_positions.name)
		self.f_ref_positions = StructWriter(
			fopen(self.f_ref_positions.name, 'ab'),
			encoding=self.encoding)
		self._fire_event('end_sort')

	def _resolve_aliases(self: "typing.Self"):
		self._fire_event('begin_resolve_aliases')
		self.f_aliases.finalize()
		with MultiFileReader(
			self.f_ref_positions.name,
			self.f_refs.name,
		) as f_ref_list:
			ref_list = RefList(f_ref_list, self.encoding, count=self.ref_count)
			ref_dict = ref_list.as_dict()
			with Slob(self.aliases_path) as aliasesSlob:
				aliases = aliasesSlob.as_dict()
				path = os.path.join(self.tmpdir.name, 'resolved-aliases')
				alias_writer = Writer(
					path,
					workdir=self.tmpdir.name,
					max_redirects=0,
					compression=None,
				)

				def read_key_frag(item, default_fragment):
					key_frag = pickle.loads(item.content)
					if isinstance(key_frag, str):
						return key_frag, default_fragment
					return key_frag

				for item in aliasesSlob:
					from_key = item.key
					keys = set()
					keys.add(from_key)
					to_key, fragment = read_key_frag(item, item.fragment)
					count = 0
					while count <= self.max_redirects:
						# is target key itself a redirect?
						try:
							orig_to_key = to_key
							to_key, fragment = read_key_frag(
								next(aliases[to_key]),
								fragment,
							)
							count += 1
							keys.add(orig_to_key)
						except StopIteration:
							break
					if count > self.max_redirects:
						self._fire_event('too_many_redirects', from_key)
					target_ref: Ref
					try:
						target_ref = cast(Ref, next(ref_dict[to_key]))
					except StopIteration:
						self._fire_event('alias_target_not_found', to_key)
					else:
						for key in keys:
							ref = Ref(
								key=key,
								bin_index=target_ref.bin_index,
								item_index=target_ref.item_index,
								# last fragment in the chain wins
								fragment=target_ref.fragment or fragment,
							)
							alias_writer.add(pickle.dumps(ref), key)

				alias_writer.finalize()

		with Slob(path) as resolved_aliases_reader:
			previous_key = None
			for item in resolved_aliases_reader:
				ref = pickle.loads(item.content)
				if ref.key == previous_key:
					continue
				self._write_ref(
					ref.key,
					ref.bin_index,
					ref.item_index,
					ref.fragment,
				)
				previous_key = ref.key
		self._sort()
		self._fire_event('end_resolve_aliases')

	def finalize(self: "typing.Self"):
		self._fire_event('begin_finalize')
		if self.current_bin is not None:
			self._write_current_bin()

		self._sort()
		if self.max_redirects:
			self._resolve_aliases()

		files = (
			self.f_ref_positions,
			self.f_refs,
			self.f_store_positions,
			self.f_store,
		)
		for f in files:
			f.close()

		buf_size = 10 * 1024 * 1024

		with fopen(self.filename, mode='wb') as output_file:
			out = StructWriter(output_file, self.encoding)
			out.write(MAGIC)
			out.write(uuid4().bytes)
			out.write_tiny_text(self.encoding, encoding=UTF8)
			out.write_tiny_text(self.compression)

			def write_tags(tags, f):
				f.write(pack(U_CHAR, len(tags)))
				for key, value in tags.items():
					f.write_tiny_text(key)
					f.write_tiny_text(value, editable=True)
			write_tags(self.tags, out)

			def write_content_types(content_types, f):
				count = len(content_types)
				f.write(pack(U_CHAR, count))
				types = sorted(content_types.items(), key=lambda x: x[1])
				for content_type, _ in types:
					f.write_text(content_type)
			write_content_types(self.content_types, out)

			out.write_int(self.blob_count)
			store_offset = (
				out.tell() +
				U_LONG_LONG_SIZE +  # this value
				U_LONG_LONG_SIZE +  # file size value
				U_INT_SIZE +  # ref count value
				os.stat(self.f_ref_positions.name).st_size +
				os.stat(self.f_refs.name).st_size
			)
			out.write_long(store_offset)
			out.flush()

			file_size = (
				out.tell() +  # bytes written so far
				U_LONG_LONG_SIZE +  # file size value
				2 * U_INT_SIZE  # ref count and bin count
			)
			file_size += sum((os.stat(f.name).st_size for f in files))
			out.write_long(file_size)

			def mv(src, out):
				fname = src.name
				self._fire_event('begin_move', fname)
				with fopen(fname, mode='rb') as f:
					while True:
						data = f.read(buf_size)
						if len(data) == 0:
							break
						out.write(data)
						out.flush()
				os.remove(fname)
				self._fire_event('end_move', fname)

			out.write_int(self.ref_count)
			mv(self.f_ref_positions, out)
			mv(self.f_refs, out)

			out.write_int(self.bin_count)
			mv(self.f_store_positions, out)
			mv(self.f_store, out)

		self.f_ref_positions = None
		self.f_refs = None
		self.f_store_positions = None
		self.f_store = None

		self.tmpdir.cleanup()
		self._fire_event('end_finalize')

	def size_header(self: "typing.Self"):
		size = 0
		size += len(MAGIC)
		size += 16  # uuid bytes
		size += U_CHAR_SIZE + len(self.encoding.encode(UTF8))
		size += U_CHAR_SIZE + len(self.compression.encode(self.encoding))

		size += U_CHAR_SIZE  # tag length
		size += U_CHAR_SIZE  # content types count

		# tags and content types themselves counted elsewhere

		size += U_INT_SIZE  # blob count
		size += U_LONG_LONG_SIZE  # store offset
		size += U_LONG_LONG_SIZE  # file size
		size += U_INT_SIZE  # ref count
		size += U_INT_SIZE  # bin count

		return size

	def size_tags(self: "typing.Self"):
		size = 0
		for key, _ in self.tags.items():
			size += U_CHAR_SIZE + len(key.encode(self.encoding))
			size += 255
		return size

	def size_content_types(self: "typing.Self"):
		size = 0
		for content_type in self.content_types:
			size += U_CHAR_SIZE + len(content_type.encode(self.encoding))
		return size

	def size_data(self: "typing.Self"):
		files = (
			self.f_ref_positions,
			self.f_refs,
			self.f_store_positions,
			self.f_store,
		)
		return sum((os.stat(f.name).st_size for f in files))

	def __enter__(self: "typing.Self"):
		return self

	def close(self):
		for _file in (
			self.f_ref_positions,
			self.f_refs,
			self.f_store_positions,
			self.f_store,
		):
			if _file is None:
				continue
			self._fire_event('WARNING: closing without finalize()')
			try:
				_file.close()
			except Exception:
				pass
		if self.tmpdir and isdir(self.tmpdir.name):
			self.tmpdir.cleanup()
		self.tmpdir = None

	def __exit__(self: "typing.Self", exc_type, exc_val, exc_tb):
		"""
		it used to call self.finalize() here
		that was bad!
		__exit__ is not meant for doing so much as finalize() is doing!
		so make sure to call writer.finalize() after you are done!
		"""
		self.close()
		return False
