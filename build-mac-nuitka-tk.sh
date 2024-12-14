#!/bin/bash
set -e
# windows nuitka github action generated
#Nuitka-Options: Used command line options: --standalone --mode=app --include-package-data=pyglossary --include-data-files=about=about --include-data-files=_license-dialog=_license-dialog --include-data-files=_license-dialog=license-dialog --include-data-dir=res=res --include-data-dir="plugins-meta=plugins-meta     " --include-module="lzo " --include-module="lxml " --include-module=tkinter --include-module=pymorphy2 --include-module=polib --include-module=yaml --include-module=bs4 --include-module=html5lib --include-module=icu --include-module="colorize_pinyin " --include-package=pyglossary --noinclude-data-files=tests --noinclude-data-files=scripts --include-plugin-directory=plugins-meta --include-plugin-directory=res --nofollow-import-to=gtk --nofollow-import-to=gi --nofollow-import-to=prompt_toolkit --nofollow-import-to=pyqt4 --assume-yes-for-downloads --clang --windows-icon-from-ico=res\pyglossary.ico --output-dir=dist.nuitka.tk --output-file=pyglossary.exe --script-name=main.py --enable-plugins=no-qt --en

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
  uv pip install -U --extra-index-url https://glowinthedark.github.io/python-lzo/ --extra-index-url https://glowinthedark.github.io/pyicu-build --index-strategy unsafe-best-match beautifulsoup4 colorize_pinyin git+https://github.com/glowinthedark/python-romkan.git html5lib libzim lxml marisa-trie mistune polib prompt-toolkit pygments pyicu pymorphy2 python-idzip python-lzo pyyaml PyYAML tqdm xxhash
  echo
  echo "USING VENV: $VIRTUAL_ENV"
  echo
fi

# Variables
MAIN_SCRIPT="main.py"
APPNAME="PyGlossaryTK"
OUTPUT_DIR="dist.nuitka.tk"
RESOURCE_DIR="resources"  # Directory with app resources (images, etc.)
#ARCH="universal"          # Options: arm64, x86_64, universal
VERSION=$(git describe --abbrev=0)
TAG=$(git describe)
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')

cp $MAIN_SCRIPT $APPNAME.py

echo "[$0]: patching files..."
git checkout HEAD -- pyglossary/ui/argparse_main.py pyglossary/ui/runner.py
rm -rf __init__.py  # get it out of the way during build or pyinstaller gets confused
sed -i '' 's/default="auto"/default="tk"/g' pyglossary/ui/argparse_main.py
sed -i '' 's/^\s*ui_list = \["gtk", "tk", "web"\]/ui_list = \["tk", "gtk", "web"\]/' pyglossary/ui/runner.py
sed -i '' 's/self\.tk_inter_version in ("8\.5", "8\.6")/self.tk_inter_version in ("8.5", "8.6", "9.0")/' .venv/lib/python${PYTHON_VERSION}/site-packages/nuitka/plugins/standard/TkinterPlugin.py

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
    cp -rv {plugins-meta,res} $OUTPUT_DIR/$APPNAME.app/Contents/MacOS

    # symlinking doesn't seem to work
    # ln -s ../Resources/pyglossary $OUTPUT_DIR/$APPNAME.app/Contents/MacOS/glossary

    # make DMG
  DMG_FILE="$APPNAME-tk-macos13-arm64-$TAG.dmg"

  [[ -f "$DMG_FILE" ]] && rm "$DMG_FILE"

  create-dmg --volname "$APPNAME $VERSION" --volicon res/pyglossary.icns --eula LICENSE  --app-drop-link 50 50 "$DMG_FILE" "$OUTPUT_DIR/$APPNAME.app"

else
    echo "ERROR: build failed!"
fi

# Code sign the app (optional)
#if command -v codesign &>/dev/null ; then
#    echo "Code signing the application bundle..."
#    codesign --deep --force --sign - "$OUTPUT_DIR/$APPNAME.app"
#fi

echo "[$0]: restoring patched files..."
git checkout HEAD -- pyglossary/ui/argparse_main.py pyglossary/ui/runner.py __init__.py
echo "all done!"
