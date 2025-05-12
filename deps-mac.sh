#!/usr/bin/env bash

set -e 
set -x

[[ -f .venv/bin/activate ]] || { echo "venv not activated! run: 'uv venv && source .venv/bin/activate'"; exit 1; }

source .venv/bin/activate

brew install lzo libffi gettext pkg-config intltool icu4c python-tk

# WITH GTK deps
# brew install lzo glib libffi gettext pygobject3 gtk+3 pkg-config py3cairo cairo intltool icu4c python-tk

PREFIX=$(brew --prefix)

export C_INCLUDE_PATH=$PREFIX/Cellar/lzo/2.10/include:$PREFIX/Cellar/lzo/2.10/include/lzo
export LIBRARY_PATH=$PREFIX/lib
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig:$PREFIX/opt/icu4c/lib/pkgconfig
export LDFLAGS="-L$PREFIX/opt/icu4c/lib -L$PREFIX/opt/libffi/lib"
export CPPFLAGS="-I$PREFIX/opt/icu4c/include -I$PREFIX/opt/libffi/include"

# ensure uv is available
command -v uv &>/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh

[ "$0" = "-zsh" ] && rehash

uv pip install -U pymorphy2 biplist lxml polib PyYAML beautifulsoup4 html5lib PyICU python-lzo prompt_toolkit colorize_pinyin
# WITH GTK
# uv pip install -U pymorphy2 biplib lxml polib PyYAML beautifulsoup4 html5lib PyICU python-lzo prompt_toolkit gobject pygobject pycairo colorize_pinyin
# uv pip install .
