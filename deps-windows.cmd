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

uv pip install -U pymorphy2 lxml polib PyYAML beautifulsoup4 html5lib prompt_toolkit nuitka colorize_pinyin wheel setuptools

rem if not present install pyicu from https://github.com/cgohlke/pyicu-build/releases

python -c "import icu" 2>NUL

if %errorlevel% neq 0 (
    echo "pyicu module not found - installing WHL module..."
    uv pip install https://github.com/cgohlke/pyicu-build/releases/download/v2.14/PyICU-2.14-cp312-cp312-win_amd64.whl
)


rem install python-lzo if not available

python -c "import lzo" 2>NUL

if %errorlevel% neq 0 (
    echo "python-lzo module not found - installing WHL module..."
    uv pip install https://github.com/glowinthedark/python-lzo/releases/download/v1.16/python_lzo-1.16-cp312-cp312-win_amd64.whl

    rem "OR build from source - vsbuildtools MUST be installed; see https://github.com/bycloudai/InstallVSBuildToolsWindows..."
    rem uv pip install git+https://github.com/jd-boyd/python-lzo
)
