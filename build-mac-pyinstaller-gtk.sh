#!/usr/bin/env bash

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
  echo
  echo "USING VENV: $VIRTUAL_ENV"
  echo
fi

PREFIX=$(brew --prefix)
DIST_DIR=dist.pyinstaller
APPNAME=PyGlossaryGtk
VERSION=$(git describe --abbrev=0)
TAG=$(git describe)

mv __init__.py __init__.py.txt # get it out of the way during build or pyinstaller gets confused
sed -i '' 's/default="auto"/default="gtk"/g' pyglossary/ui/argparse_main.py
cp ../pyglossary-glo/pyglossary/ui/ui_tk.py pyglossary/ui

pyinstaller --noupx \
    --windowed \
    --noconfirm \
    --exclude-module tkinter \
    --osx-bundle-identifier com.github.pyglossary \
    --debug bootloader \
    --icon res/pyglossary.icns \
    --collect-submodules pyglossary \
    --collect-all pyglossary \
    --collect-all gi \
    --argv-emulation \
    --hidden-import msvcrt \
    --hidden-import pyglossary \
    --hidden-import platform \
    --hidden-import json \
    --hidden-import __future__ \
    --hidden-import uuid  \
    --hidden-import pkgutil \
    --hidden-import shlex \
    --hidden-import prompt_toolkit \
    --hidden-import Gtk \
    --hidden-import gi \
    --paths '.:pyglossary:pyglossary/ui:pyglossary/plugins:pyglossary/glossary_v2:pyglossary/langs' \
    --name $APPNAME \
    --distpath "$DIST_DIR" \
    --workpath build.pyinstaller \
    pyglossary.pyw

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
    create-dmg --volname "PyGlossary $VERSION" --volicon res/pyglossary.icns --eula LICENSE  --app-drop-link 50 50 "$APPNAME-macOS-$TAG.dmg" "$DIST_DIR/$APPNAME.app"

else
    echo "ERROR: build failed!"
fi

pwd
# restore original
mv __init__.py.txt __init__.py 

