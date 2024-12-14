#!/bin/bash

set -e

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
  uv pip install -U --extra-index-url https://glowinthedark.github.io/python-lzo/ --extra-index-url https://glowinthedark.github.io/pyicu-build --index-strategy unsafe-best-match nuitka beautifulsoup4 colorize_pinyin git+https://github.com/glowinthedark/python-romkan.git html5lib libzim lxml marisa-trie mistune polib prompt-toolkit pygments pyicu pymorphy2 python-idzip python-lzo pyyaml PyYAML tqdm xxhash
  echo
  echo "USING VENV: $VIRTUAL_ENV"
  echo
fi

# Variables
MAIN_SCRIPT="main.py"
APPNAME="PyGlossaryWeb"
OUTPUT_DIR="dist.nuitka.web"
VERSION=$(git describe --abbrev=0)
TAG=$(git describe)

cp $MAIN_SCRIPT $APPNAME.py

echo "[$0]: patching files..."
git checkout HEAD -- pyglossary/ui/argparse_main.py pyglossary/ui/runner.py
rm -rf __init__.py  # get it out of the way during build or pyinstaller gets confused
sed -i '' 's/default="gtk"/default="web"/g' pyglossary/ui/argparse_main.py
sed -i '' 's/default="tk"/default="web"/g' pyglossary/ui/argparse_main.py
sed -i '' 's/default="auto"/default="web"/g' pyglossary/ui/argparse_main.py
sed -i '' 's/^\s*ui_list = \["gtk", "tk", "web"\]/ui_list = \["web", "gtk", "tk"\]/' pyglossary/ui/runner.py
sed -i '' 's/\s*ui_list = \["tk", "gtk", "web"\]/ui_list = \["web", "tk", "gtk"\]/' pyglossary/ui/runner.py

# NOT SUPPORTED (YET)
#	--macos-target-arch=$ARCH \

python -m nuitka \
	--standalone \
	--assume-yes-for-downloads \
	--follow-imports \
	--macos-create-app-bundle \
	--macos-app-icon=res/pyglossary.icns \
	--macos-signed-app-name="$APPNAME" \
	--macos-app-name="$APPNAME" \
	--macos-app-mode=background \
	--include-package=pyglossary \
	--nofollow-import-to=tkinter \
	--nofollow-import-to=pyglossary.ui.ui_gtk \
	--nofollow-import-to=pyglossary.ui.ui_gtk4 \
	--nofollow-import-to=pyglossary.ui.ui_tk \
	--nofollow-import-to=pyglossary.ui.ui_qt \
	--nofollow-import-to=gi \
	--nofollow-import-to=gtk \
	--nofollow-import-to=pyqt4 \
	--nofollow-import-to=pyqt5 \
	--nofollow-import-to=pyqt6 \
	--nofollow-import-to=*.tests \
	--noinclude-pytest-mode=nofollow \
	--noinclude-setuptools-mode=nofollow \
	--plugin-disable=tk-inter \
	--plugin-disable=pyqt5 \
	--include-module=lzo \
	--include-module=pymorphy2 \
	--include-module=lxml \
	--include-module=polib \
	--include-module=yaml \
	--include-module=bs4 \
	--include-module=html5lib \
	--include-module=icu \
	--include-module=colorize_pinyin \
	--include-package-data=pyglossary \
	--include-data-files=about=about \
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
    cp -rv {plugins-meta,res,pyglossary} $OUTPUT_DIR/$APPNAME.app/Contents/MacOS

    # symlinking doesn't seem to work
    # ln -s ../Resources/pyglossary $OUTPUT_DIR/$APPNAME.app/Contents/MacOS/glossary

    # make DMG
  DMG_FILE="$APPNAME-WEB-macos13-arm64-$TAG.dmg"

  [[ -f "$DMG_FILE" ]] && rm "$DMG_FILE"

  create-dmg --volname "$APPNAME-WEB $VERSION" --volicon res/pyglossary.icns --eula LICENSE  --app-drop-link 50 50 "$DMG_FILE" "$OUTPUT_DIR/$APPNAME.app"
  create-dmg --volname "$APPNAME-WEB $VERSION" --volicon res/pyglossary.icns --eula LICENSE  --app-drop-link 50 50 "$DMG_FILE" "$OUTPUT_DIR/$APPNAME.app"

else
    echo "ERROR: build failed!"
fi

# Code sign the app (optional)
#if command -v codesign &>/dev/null; then
#    echo "Code signing the application bundle..."
#    codesign --deep --force --sign - "$APP_BINARY"
#fi

echo "[$0]: restoring patched files..."
git checkout HEAD -- pyglossary/ui/argparse_main.py pyglossary/ui/runner.py __init__.py
echo "all done!"
