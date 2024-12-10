#!/usr/bin/env bash

set -e
trap 'echo "Build failed" >&2; exit 1' ERR

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
  uv pip install -r requirements-web.txt --extra-index-url https://glowinthedark.github.io/python-lzo/ --extra-index-url https://glowinthedark.github.io/pyicu-build --index-strategy unsafe-best-match
  echo
  echo "USING VENV: $VIRTUAL_ENV"
  echo
fi

PREFIX=$(brew --prefix)
MAIN_SCRIPT="main.py"
DIST_DIR=dist.pyinstaller.TK
APPNAME=PyGlossaryTkPin
VERSION=$(git describe --abbrev=0)
TAG=$(git describe)

git checkout HEAD -- pyglossary/ui/argparse_main.py pyglossary/ui/runner.py

rm __init__.py # get it out of the way or pyinstaller gets confused
sed -i '' 's/default="auto"/default="tk"/g' pyglossary/ui/argparse_main.py

pyinstaller --noupx \
    --windowed \
    --noconfirm \
    --hidden-import tkinter \
    --osx-bundle-identifier com.github.pyinstaller.pyglossary.tk \
    --debug bootloader \
    --icon res/pyglossary.icns \
    --collect-submodules pyglossary \
    --collect-all pyglossary \
    --argv-emulation \
    --hidden-import msvcrt \
    --hidden-import platform \
    --hidden-import json \
    --hidden-import __future__ \
    --hidden-import uuid  \
    --hidden-import pkgutil \
    --hidden-import shlex \
    --exclude-module prompt_toolkit \
    --exclude-module Gtk \
    --exclude-module gi \
    --paths '.:pyglossary:pyglossary/ui:pyglossary/plugins:pyglossary/glossary_v2:pyglossary/langs' \
    --name $APPNAME \
    --distpath "$DIST_DIR" \
    --workpath build.pyinstallerTK \
    $MAIN_SCRIPT

    # --collect-data pyglossary \
    # --collect-binaries pyglossary \
    # --add-data 'pyglossary:.' \
    # --add-data 'pyglossary/plugins:plugins' \
    # --add-data 'pyglossary/plugin_lib:plugin_lib' \
    # --add-data 'pyglossary/langs:langs' \
    # --add-data 'pyglossary/sort_modules:sort_modules' \
    # --add-data 'pyglossary/ui:ui' \
    # --add-data 'pyglossary/glossary_progress.py:pyglossary' \
    # --add-data 'pyglossary/glossary_progress.py:pyglossary' \
    # --add-data 'pyglossary/xdxf:pyglossary/xdxf' \

# pyinstaller --noconfirm PyGlossary_main.spec

if [ -d "$DIST_DIR/$APPNAME.app/Contents/MacOS/" ]; then
    cp -r {about,AUTHORS,_license-dialog,LICENSE,config.json,help} $DIST_DIR/$APPNAME.app/Contents/MacOS
    cp -rv _license-dialog $DIST_DIR/$APPNAME.app/Contents/MacOS/license-dialog
    cp -rv {plugins-meta,res,pyglossary} $DIST_DIR/$APPNAME.app/Contents/MacOS
    
    # symlinking doesn't seem to work
    # ln -s ../Resources/pyglossary $DIST_DIR/$APPNAME.app/Contents/MacOS/glossary

    # make DMG
#    create-dmg --volname "PyGlossaryTk $VERSION" --volicon res/pyglossary.icns --eula LICENSE  --app-drop-link 50 50 "PyGlossaryTk-macOS-$TAG.dmg" "$DIST_DIR/PyGlossaryTk.app"

else
    echo "ERROR: build failed!"
fi

pwd
# restore originals
git checkout HEAD -- __init__.py pyglossary/ui/argparse_main.py pyglossary/ui/runner.py


