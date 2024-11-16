brew install lzo glib pkg-config py3cairo cairo
# brew install pygobject3 gtk4 lzo
source .venv/bin/activate

export C_INCLUDE_PATH=/opt/homebrew/Cellar/lzo/2.10/include:/opt/homebrew/Cellar/lzo/2.10/include/lzo
export LIBRARY_PATH=/opt/homebrew/lib

# ensure uv is available
command -v uv &>/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh

[ "$0" = "-zsh" ] && rehash



uv pip install -U python-lzo
# python -m pip install python-lzo

export PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig
# export PKG_CONFIG_PATH=$(brew --prefix glib)/lib/pkgconfig

# NO GTK!
# uv pip install -U pymorphy2 lxml polib PyYAML beautifulsoup4 pyglossary html5lib PyICU python-lzo prompt_toolkit pyinstaller 

# WITH GTK!
uv pip install -U pymorphy2 lxml polib PyYAML beautifulsoup4 html5lib PyICU python-lzo prompt_toolkit gobject pygobject pycairo pyinstaller 
uv pip install .
# python -m pip install --upgrade lxml polib PyYAML beautifulsoup4 html5lib PyICU python-lzo prompt_toolkit
