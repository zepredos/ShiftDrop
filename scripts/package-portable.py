#!/usr/bin/env python3
"""Build on the target OS; PyInstaller does not cross-compile native binaries."""

import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
VERSION = '0.2.0'


def extension_archive():
    target = ROOT / 'dist' / 'shiftdrop-gnome-extension.zip'
    target.parent.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'linux/gnome/shiftdrop@local.shiftdrop'
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(source.rglob('*')):
            if path.is_file(): archive.write(path, path.relative_to(source))
    return target


def main():
    if '--extension-only' in sys.argv[1:]:
        print(extension_archive())
        return
    if sys.platform not in ('linux','win32'):
        print(extension_archive())
        raise SystemExit('Build the desktop binary on Linux or Windows; use the native Swift build on macOS.')
    subprocess.run([sys.executable,'-m','PyInstaller','--noconfirm','--clean','--onedir','--windowed',
        '--name','ShiftDrop','--paths',str(ROOT/'portable'),'--distpath',str(ROOT/'dist/portable'),
        '--workpath',str(ROOT/'.build/portable'),'--specpath',str(ROOT/'.build'),
        '--collect-all','pypdfium2_raw','--collect-all','pillow_heif','--collect-data','reportlab',
        '--exclude-module','PySide6.QtQml','--exclude-module','PySide6.QtQuick',
        '--exclude-module','PySide6.QtTest',str(ROOT/'scripts/portable-entry.py')],check=True,cwd=ROOT)
    os_name = 'linux' if sys.platform=='linux' else 'windows'
    name = f'ShiftDrop-{VERSION}-{os_name}-{platform.machine().lower()}'
    with tempfile.TemporaryDirectory(prefix='shiftdrop-package-') as directory:
        stage = Path(directory)/name; stage.mkdir()
        shutil.copytree(ROOT/'dist/portable/ShiftDrop',stage/'ShiftDrop')
        shutil.copytree(ROOT/'linux',stage/'linux',ignore=shutil.ignore_patterns('tests'))
        scripts = stage/'scripts'; scripts.mkdir()
        for installer in ('install-linux.py','install-windows.ps1'):
            shutil.copy2(ROOT/'scripts'/installer,scripts/installer)
        shutil.copy2(ROOT/'README.md',stage/'README.md')
        shutil.copytree(ROOT/'docs',stage/'docs')
        with (stage/'DEPENDENCIES.txt').open('w') as handle:
            subprocess.run([sys.executable,'-m','pip','list','--format=freeze','--exclude','shiftdrop'],stdout=handle,check=True)
        # License files remain in the bundled, dynamically loadable dependency directories.
        if (ROOT/'LICENSE').exists(): shutil.copy2(ROOT/'LICENSE',stage/'LICENSE')
        if (ROOT/'THIRD_PARTY_NOTICES.md').exists(): shutil.copy2(ROOT/'THIRD_PARTY_NOTICES.md',stage/'THIRD_PARTY_NOTICES.md')
        format_name = 'gztar' if os_name=='linux' else 'zip'
        output = shutil.make_archive(str(ROOT/'dist'/name),format_name,directory,name)
        print(output)
    print(extension_archive())


if __name__ == '__main__':
    main()
