#!/usr/bin/env bash

source .venv/bin/activate

# get it out of the way during build!
mv __init__.py __init__.py.txt


PREFIX=$(brew --prefix)

# CREATE MACOS SPEC
# pyinstaller --noconfirm \
#     --osx-bundle-identifier com.github.pyglossary \
#     --argv-emulation \
#     --debug all \
#     --icon res/pyglossary.icns \
#     --windowed --noupx \
#     --collect-submodules pyglossary \
#     --hidden-import msvcrt \
#     --hidden-import pyglossary \
#     --hidden-import platform \
#     --hidden-import json \
#     --hidden-import __future__ \
#     --hidden-import uuid  \
#     --hidden-import pkgutil \
#     --hidden-import shlex \
#     --hidden-import prompt_toolkit \
#     --hidden-import Gtk \
#     --hidden-import gi \
#     --paths '.:pyglossary:pyglossary/ui:pyglossary/plugins:pyglossary/glossary_v2:pyglossary/langs' \
#     --recursive-copy-metadata pyglossary \
#     --name PyGlossary_main \
#     --add-binary "$PREFIX/Cellar/icu4c/74.2/lib/libicui18n.74.dylib:Contents/Frameworks" \
#     --add-binary "$PREFIX/Cellar/icu4c/74.2/lib/libicuuc.74.dylib:Contents/Frameworks" \
#     --add-binary "$PREFIX/Cellar/icu4c/74.2/lib/libicudata.74.dylib:Contents/Frameworks" \
#     pyglossary.pyw

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

APPNAME=PyGlossary_main
rm -rf {build,dist}



pyinstaller --noconfirm PyGlossary_main.spec
#pyinstaller --noconfirm pyglossary.spec

if [ -d "dist/$APPNAME.app/Contents/MacOS/" ]; then
    cp -r {about,AUTHORS,_license-dialog,config.json,plugins-meta} dist/$APPNAME.app/Contents/MacOS
    cp -rv _license-dialog dist/$APPNAME.app/Contents/MacOS/license-dialog
    cp -rv res dist/$APPNAME.app/Contents/MacOS
    cp -rv pyglossary dist/$APPNAME.app/Contents/MacOS
else
    echo "ERROR: pyinstaller build not found!"
fi

# restore original
mv __init__.py.txt __init__.py 