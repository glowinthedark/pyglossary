# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_data_files
from PyInstaller.utils.hooks import collect_dynamic_libs
from PyInstaller.utils.hooks import collect_submodules
from PyInstaller.utils.hooks import collect_all
from PyInstaller.utils.hooks import copy_metadata

datas = [('about', '.'), ('LICENSE', '.'), ('res', 'res'), ('pyglossary', '.'), ('pyglossary/plugins', 'plugins'), ('pyglossary/plugin_lib', 'plugin_lib'), ('pyglossary/langs', 'langs'), ('pyglossary/sort_modules', 'sort_modules'), ('pyglossary/ui', 'ui'), ('pyglossary/glossary_progress.py', 'pyglossary'), ('pyglossary/glossary_progress.py', 'pyglossary'), ('pyglossary/xdxf', 'pyglossary/xdxf')]
binaries = []
hiddenimports = ['msvcrt', 'pyglossary', 'platform', 'json', '__future__', 'uuid', 'pkgutil', 'shlex', 'prompt_toolkit']
datas += collect_data_files('pyglossary')
datas += copy_metadata('pyglossary', recursive=True)
binaries += collect_dynamic_libs('pyglossary')
hiddenimports += collect_submodules('pyglossary')
tmp_ret = collect_all('pyglossary')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]


a = Analysis(
    ['pyglossary.pyw'],
    pathex=['.', 'pyglossary', 'pyglossary/ui', 'pyglossary/plugins', 'pyglossary/glossary_v2', 'pyglossary/langs'],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=True,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [('v', None, 'OPTION')],
    exclude_binaries=True,
    name='PyGlossary_main',
    debug=True,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=True,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['res/pyglossary.icns'],
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name='PyGlossary_main',
)
app = BUNDLE(
    coll,
    name='PyGlossary_main.app',
    icon='res/pyglossary.icns',
    bundle_identifier='com.github.pyglossary',
)
