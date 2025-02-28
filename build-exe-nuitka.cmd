@echo off

if "%VIRTUAL_ENV%" == "" (
    echo Not in a venv! Quitting...
    echo  - 1. to create venv use: uv venv
    echo  - 2. to activate existing venv use: .venv\Scripts\activate
    echo Install uv with:
    echo    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
    exit /b 1
) else (
	echo.
    echo venv found: %VIRTUAL_ENV% - READY TO BUILD!
    echo.
    pause
    python -m pip install -U --extra-index-url https://glowinthedark.github.io/python-lzo/ --extra-index-url https://glowinthedark.github.io/pyicu-build --index-strategy unsafe-best-match nuitka beautifulsoup4 colorize_pinyin html5lib libzim lxml marisa-trie mistune polib prompt-toolkit pygments pyicu pymorphy2 python-idzip python-lzo pyyaml PyYAML tqdm xxhash

)

set OUTPUT_DIR=build.PyGlossaryWinNuitka

python -m nuitka --assume-yes-for-downloads --plugin-enable=dll-files --plugin-enable=anti-bloat --follow-imports --standalone --windows-console-mode=disable --windows-icon-from-ico=res\pyglossary.ico --enable-plugin=tk-inter --include-package=pyglossary --include-module=tkinter --include-module=lzo --include-module=pymorphy2 --include-module=lxml --include-module=polib --include-module=yaml --include-module=bs4 --include-module=html5lib --include-module=icu --include-module=colorize_pinyin --include-package-data=pyglossary --include-data-files=about=about --include-data-files=_license-dialog=_license-dialog --include-data-files=_license-dialog=license-dialog --noinclude-custom-mode=unittest:nofollow main.py --output-dir="%OUTPUT_DIR%" --output-filename=pyglossary.exe
 
python -c "import shutil; shutil.copy('_license-dialog', "%OUTPUT_DIR%\main.dist")
python -c "import shutil; shutil.copy('about, "%OUTPUT_DIR%\main.dist")
python -c "import shutil; shutil.copy('AUTHORS, "%OUTPUT_DIR%\main.dist")
python -c "import shutil; shutil.copy('config.json, "%OUTPUT_DIR%\main.dist")
python -c "import shutil; shutil.copytree('plugins-meta', "%OUTPUT_DIR%/main.dist/plugins-meta", dirs_exist_ok=True)"
python -c "import shutil; shutil.copytree('res', "%OUTPUT_DIR%/main.dist/res", dirs_exist_ok=True)"
