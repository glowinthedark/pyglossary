#!/usr/bin/env bash

source .venv/bin/activate

# get it out of the way during build!
mv __init__.py __init__.py.txt

# GENERATE MACOS SPEC - 1st time
# pyinstaller --noconfirm --osx-bundle-identifier com.github.pyglossary --argv-emulation -d all -i res/pyglossary.icns --windowed --noupx --collect-all pyglossary --hidden-import msvcrt --hidden-import pyglossary --hidden-import platform --hidden-import json --hidden-import __future__ --hidden-import uuid  --hidden-import pkgutil --hidden-import shlex --hidden-import prompt_toolkit --collect-submodules pyglossary --paths '.:pyglossary:pyglossary/ui:pyglossary/plugins:pyglossary/glossary_v2:pyglossary/langs' --recursive-copy-metadata pyglossary --collect-data pyglossary --collect-binaries pyglossary --name PyGlossary_main --add-data "about:." --add-data "LICENSE:." --add-data 'res:res' --add-data 'pyglossary:.' --add-data 'pyglossary/plugins:plugins' --add-data 'pyglossary/plugin_lib:plugin_lib' --add-data 'pyglossary/langs:langs' --add-data 'pyglossary/sort_modules:sort_modules' --add-data 'pyglossary/ui:ui' --add-data 'pyglossary/glossary_progress.py:pyglossary' --add-data 'pyglossary/glossary_progress.py:pyglossary' --add-data 'pyglossary/xdxf:pyglossary/xdxf' pyglossary.pyw

APPNAME=PyGlossary_main
rm -rf {build,dist}

pyinstaller --noconfirm PyGlossary_main.spec
#pyinstaller --noconfirm pyglossary.spec

if [ -d "dist/$APPNAME.app/Contents/MacOS/" ]; then
    cp -r {about,AUTHORS,_license-dialog,config.json,plugins-meta} dist/$APPNAME.app/Contents/MacOS
    cp -rv _license-dialog dist/$APPNAME.app/Contents/MacOS/license-dialog
    cp -rv res dist/$APPNAME.app/Contents/MacOS
    cp -rv pyglossary dist/$APPNAME.app/Contents/MacOS
    cp /opt/homebrew/Cellar/icu4c/74.2/lib/libicui18n.74.dylib dist/$APPNAME.app/Contents/Frameworks
    cp /opt/homebrew/Cellar/icu4c/74.2/lib/libicuuc.74.dylib dist/$APPNAME.app/Contents/Frameworks
    cp /opt/homebrew/Cellar/icu4c/74.2/lib/libicudata.74.dylib dist/$APPNAME.app/Contents/Frameworks
else
    echo "ERROR: pyinstaller build not found!"
fi

# restore original
mv __init__.py.txt __init__.py 