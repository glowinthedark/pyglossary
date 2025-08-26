#!/bin/bash

# DEBUG
# set -x
set -euo pipefail

if [[ -z "$VIRTUAL_ENV" ]]; then
  echo Not in a venv! Quitting...
  echo ' - 1. create a venv: uv venv'
  echo ' - 2. activate existing venv: source .venv/bin/activate'
  echo
  echo ' - install uv:'
  echo '   curl -LsSf https://astral.sh/uv/install.sh | sh'
  read -r -n 1 -s -p "any key to exit..."
  exit 1
else
  PREFIX=$(brew --prefix)
  export C_INCLUDE_PATH=$PREFIX/Cellar/lzo/2.10/include:$PREFIX/Cellar/lzo/2.10/include/lzo
  export LIBRARY_PATH=$PREFIX/lib
  export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig:$PREFIX/opt/icu4c/lib/pkgconfig
  export LDFLAGS="-L$PREFIX/opt/icu4c/lib -L$PREFIX/opt/libffi/lib"
  export CPPFLAGS="-I$PREFIX/opt/icu4c/include -I$PREFIX/opt/libffi/include"
  # uv pip install -U --extra-index-url https://glowinthedark.github.io/python-lzo/ --extra-index-url https://glowinthedark.github.io/pyicu-build --index-strategy unsafe-best-match beautifulsoup4 colorize_pinyin git+https://github.com/glowinthedark/python-romkan.git html5lib libzim lxml marisa-trie mistune polib prompt-toolkit pygments pyicu pymorphy2 python-idzip python-lzo pyyaml PyYAML tqdm xxhash
  # uv pip install -U --extra-index-url https://glowinthedark.github.io/python-lzo/ --extra-index-url https://glowinthedark.github.io/pyicu-build --index-strategy unsafe-best-match nuitka beautifulsoup4 colorize_pinyin html5lib libzim lxml marisa-trie mistune polib prompt-toolkit pygments pyicu pymorphy2 python-idzip python-lzo pyyaml tqdm xxhash

  echo
  echo "USING VENV: $VIRTUAL_ENV"
  echo
fi

# Variables
MAIN_SCRIPT="main.py"
APPNAME="PyGlossaryTK"
OUTPUT_DIR="dist.nuitka.tk"
VERSION=$(git describe --abbrev=0)
TAG=$(git describe)
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')

cp $MAIN_SCRIPT $APPNAME.py

echo "[$0]: patching files..."
git checkout HEAD -- pyglossary/ui/argparse_main.py pyglossary/ui/runner.py
rm -rf __init__.py  # get it out of the way during build or pyinstaller gets confused
sed -i '' 's/default="auto"/default="tk"/g' pyglossary/ui/argparse_main.py
sed -i '' 's/^\s*ui_list = \["gtk", "tk", "web"\]/ui_list = \["tk", "gtk", "web"\]/' pyglossary/ui/runner.py
#sed -i '' 's/self\.tk_inter_version in ("8\.5", "8\.6")/self.tk_inter_version in ("8.5", "8.6", "9.0")/' .venv/lib/python${PYTHON_VERSION}/site-packages/nuitka/plugins/standard/TkinterPlugin.py

# NOT SUPPORTED (YET)
#	--macos-target-arch=$ARCH \

if ! command -v python3 -m nuitka >/dev/null 2>&1; then
    echo "Error: Nuitka is not installed in this venv!"
    exit 1
fi

python -m nuitka \
	--standalone \
	--assume-yes-for-downloads \
	--follow-imports \
	--macos-create-app-bundle \
	--macos-app-icon=res/pyglossary.icns \
	--macos-signed-app-name="$APPNAME" \
	--macos-app-name="$APPNAME" \
	--macos-app-mode=gui \
	--enable-plugin=tk-inter \
	--include-package=pyglossary \
	--include-module=tkinter \
  --nofollow-import-to=pyglossary.ui.ui_gtk \
	--nofollow-import-to=pyglossary.ui.ui_gtk4 \
	--nofollow-import-to=pyglossary.ui.ui_qt \
	--nofollow-import-to=gi \
	--nofollow-import-to=gtk \
	--nofollow-import-to=pyqt4 \
	--nofollow-import-to=pyqt5 \
	--nofollow-import-to=pyqt6 \
	--nofollow-import-to=*.tests \
	--noinclude-pytest-mode=nofollow \
	--noinclude-setuptools-mode=nofollow \
	--plugin-disable=pyqt5 \
	--include-module=lzo \
	--include-module=pymorphy2 \
	--include-module=lxml \
	--include-module=polib \
	--include-module=yaml \
	--include-module=bs4 \
	--include-module=html5lib \
	--include-module=icu \
	--include-module=_json \
	--include-module=_bisect \
	--include-module=colorize_pinyin \
	--include-package-data=pyglossary \
	--include-data-files=about=about \
	--include-data-files=_license-dialog=_license-dialog \
	--include-data-dir=res=. \
	--include-data-files=_license-dialog=license-dialog \
	--noinclude-custom-mode=unittest:nofollow \
	--output-dir="$OUTPUT_DIR" \
	--output-filename=$APPNAME \
	$APPNAME.py || (echo "Build failed!" && exit 1)

if [ -d "$OUTPUT_DIR/$APPNAME.app/Contents/MacOS" ]; then
    cp -r {about,AUTHORS,_license-dialog,LICENSE,config.json,help} $OUTPUT_DIR/$APPNAME.app/Contents/MacOS
    cp -rv _license-dialog $OUTPUT_DIR/$APPNAME.app/Contents/MacOS/license-dialog
    cp -rv {plugins-meta,res} $OUTPUT_DIR/$APPNAME.app/Contents/MacOS


  DMG_FILE="$APPNAME-$(sw_vers --productName)$(sw_vers --productVersion | cut -d. -f1)-$(uname -m)-$TAG.dmg"
  [[ -f "$DMG_FILE" ]] && rm "$DMG_FILE"

	TMP_DIST_DIR=$(mktemp -d)
	
  ln -s /Applications "${TMP_DIST_DIR}"
	ditto -V --norsrc --noextattr --noqtn "$OUTPUT_DIR/$APPNAME.app" "${TMP_DIST_DIR}/$APPNAME.app"


  # make DMG with create-dmg if present or fallback to raw hdiutil
if command -v create-dmg &>/dev/null; then
  create-dmg --volname "$APPNAME $VERSION" --volicon res/pyglossary.icns --eula LICENSE  --app-drop-link 50 50 "$DMG_FILE" "$OUTPUT_DIR/$APPNAME.app"
else
  echo "create-dmg not found. Fall back to hdiutil..."
  hdiutil create -verbose -volname "$APPNAME $VERSION" -srcfolder "${TMP_DIST_DIR}" -ov -format UDZO -fs HFS+J "${DMG_FILE}"
fi

  rm -rf "${TMP_DIST_DIR}"

else
    echo "ERROR: build failed!"
fi

# LIST IDENTITIES:
# security find-identity -p codesigning

# Code sign the app (optional)
#if command -v codesign &>/dev/null ; then
#    echo "Code signing the application bundle..."
#    codesign --deep --force --sign - "$OUTPUT_DIR/$APPNAME.app"
#fi
#codesign -f -s FHB8TG64F4 "${DMG_FILE}"


echo "[$0]: restoring patched files..."
git checkout HEAD -- pyglossary/ui/argparse_main.py pyglossary/ui/runner.py __init__.py
echo "all done!"
