#!/usr/bin/env bash

if [[ -z "$VIRTUAL_ENV" ]]; then
  echo Not in a venv! Quitting...
  echo ' - 1. to create a venv use: uv venv'
  echo ' - 2. to activate existing venv use: source .venv/bin/activate'
  echo
  echo ' - to install uv use:'
  echo '   curl -LsSf https://astral.sh/uv/install.sh | sh'
  exit 1
else
  echo
  echo "USING venv! $VIRTUAL_ENV"
  echo
  read -r -n 1 -s -p "Press any key to install dependencies..."
fi

#[[ -f .venv/bin/activate ]] || { echo "venv not activated! run: 'uv venv && source .venv/bin/activate'"; exit 1; }

# WITHOUT GI
#brew install lzo glib libffi gettext pkg-config intltool icu4c python-tk

# with GI ???? pygobject3 (can ALSO be installed with PIP)
brew install lzo glib libffi gettext gtk+3 pkg-config py3cairo cairo intltool icu4c create-dmg

# with tkinter
# brew install lzo glib libffi gettext  pkg-config intltool icu4c python-tk

PREFIX=$(brew --prefix)

export C_INCLUDE_PATH="$(brew --prefix lzo)/include:$(brew --prefix lzo)/include/lzo"
export LIBRARY_PATH="$BREW_PREFIX/Cellar/lib"
export PKG_CONFIG_PATH="$BREW_PREFIX/Cellar/lib/pkgconfig:$(brew --prefix icu4c)/lib/pkgconfig:$(brew --prefix lzo)/lib/pkgconfig:$(brew --prefix libffi)/lib/pkgconfig:"
export LDFLAGS="-L$(brew --prefix libffi)/lib -L$(brew --prefix icu4c)/lib -L$(brew --prefix lzo)/lib"
export CPPFLAGS="-I$(brew --prefix icu4c)/include -I$(brew --prefix libffi)/include -I$(brew --prefix libffi)/include"


# export C_INCLUDE_PATH=$PREFIX/Cellar/lzo/2.10/include:$PREFIX/Cellar/lzo/2.10/include/lzo
# export LIBRARY_PATH=$PREFIX/lib
# export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig:$PREFIX/opt/icu4c/lib/pkgconfig
# export LDFLAGS="-L$PREFIX/opt/icu4c/lib -L$PREFIX/opt/libffi/lib"
# export CPPFLAGS="-I$PREFIX/opt/icu4c/include -I$PREFIX/opt/libffi/include"

# ensure uv is available
command -v uv &>/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh

[ "$0" = "-zsh" ] && rehash

# uv pip install git+https://github.com/Nuitka/Nuitka.git
# uv pip install git+https://github.com/Nuitka/Nuitka.git@factory
#uv pip install git+https://github.com/Nuitka/Nuitka.git@develop

# WITHOUT GI!!!
#uv pip install -U pymorphy2 lxml polib PyYAML beautifulsoup4 html5lib PyICU python-lzo prompt_toolkit colorize_pinyin
# with GI

# WARNING GOBJECT is installed EITHER with brew install pygobject3 ORRRRR pip3 install PyGObject
uv pip install pyinstaller
uv pip install -U pymorphy2 lxml polib PyYAML beautifulsoup4 html5lib PyICU python-lzo prompt_toolkit gobject pygobject pycairo colorize_pinyin
uv pip install .
