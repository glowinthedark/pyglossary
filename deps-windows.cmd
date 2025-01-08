@echo off

if "%VIRTUAL_ENV%" == "" (
    echo Not in a venv! Quitting...
    echo  - 1. to create venv use: uv venv
    echo  - 2. to activate existing venv use: .venv\Scripts\activate
    exit /b 1
) else (
	echo.
    echo venv found: %VIRTUAL_ENV% Good!
    echo.
    pause
)

rem SEE: https://github.com/Nuitka/Nuitka/issues/1728

rem Check if we have 'uv' in PATH

where uv.exe >nul 2>&1

if %errorlevel% neq 0 (
    echo "ERROR: 'uv.exe' not found in PATH. Install 'uv' by running from PowerShell console:"
    echo.
    echo powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
    echo.
    pause
    exit /b 1
)

uv pip install .

uv pip install -U PyYAML beautifulsoup4 biplist colorize_pinyin html5lib libzim lxml marisa-trie mistune polib prompt-toolkit pygments pymorphy2 python-idzip python-idzip python-romkan-ng pyyaml tqdm xxhash

rem if not present install pyicu from https://github.com/cgohlke/pyicu-build/releases

python -c "import icu" 2>NUL

if %errorlevel% neq 0 (
    echo "pyicu module not found - installing WHL module..."
    uv pip install pyicu --extra-index-url https://glowinthedark.github.io/pyicu-build --index-strategy unsafe-best-match
)


rem install python-lzo if not available

python -c "import lzo" 2>NUL

if %errorlevel% neq 0 (
    echo "python-lzo module not found - installing WHL module..."
    uv pip install python-lzo --extra-index-url https://glowinthedark.github.io/pyicu-build --index-strategy unsafe-best-match

    rem "OR build from source - vsbuildtools MUST be installed; see https://github.com/bycloudai/InstallVSBuildToolsWindows..."
    rem uv pip install git+https://github.com/jd-boyd/python-lzo
)
