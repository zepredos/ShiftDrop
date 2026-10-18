#!/usr/bin/env python3
"""Install ShiftDrop into this user's home directory. Never needs sudo."""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import venv

APP_ID = 'io.github.shiftdrop.ShiftDrop'
UUID = 'shiftdrop@local.shiftdrop'
ROOT = Path(__file__).resolve().parent.parent


def desktop_quote(path):
    value = str(path)
    for character in ('\\', '"', '`', '$'):
        value = value.replace(character, '\\' + character)
    return '"' + value + '"'


def install(*, with_extension=True):
    if sys.platform != 'linux':
        raise SystemExit('Run this installer on Linux. The existing native Mac app is separate.')
    base = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')))
    target = base / 'shiftdrop'
    target.mkdir(parents=True, exist_ok=True)
    bundle = ROOT / 'ShiftDrop'
    if (bundle / 'ShiftDrop').is_file():
        application = target / 'app'
        shutil.copytree(bundle, application, dirs_exist_ok=True)
        command = [str(application / 'ShiftDrop')]
    else:
        environment = target / 'venv'
        venv.EnvBuilder(with_pip=True).create(environment)
        python = environment / 'bin/python'
        subprocess.run([str(python), '-m', 'pip', 'install', str(ROOT)], check=True)
        command = [str(python), '-m', 'shiftdrop']
    launcher = Path.home() / '.local/bin/shiftdrop'
    launcher.parent.mkdir(parents=True, exist_ok=True)
    launcher.write_text('#!/bin/sh\nexec ' + shlex.join(command) + ' "$@"\n', encoding='utf-8')
    launcher.chmod(0o755)
    applications = base / 'applications'; applications.mkdir(parents=True, exist_ok=True)
    (applications / (APP_ID + '.desktop')).write_text(
        '[Desktop Entry]\nType=Application\nName=ShiftDrop\nComment=Local file conversions with drag + Shift\n'
        f'Exec={desktop_quote(launcher)} %F\nIcon={APP_ID}\nTerminal=false\nCategories=Utility;Graphics;\n'
        'MimeType=image/png;image/jpeg;image/webp;image/heic;image/avif;image/tiff;application/pdf;text/plain;\n'
        f'StartupWMClass={APP_ID}\n', encoding='utf-8')
    services = base / 'dbus-1/services'; services.mkdir(parents=True, exist_ok=True)
    (services / (APP_ID + '.service')).write_text(
        f'[D-BUS Service]\nName={APP_ID}\nExec={desktop_quote(launcher)} --background\n', encoding='utf-8')
    icons = base / 'icons/hicolor/scalable/apps'; icons.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'linux/resources' / (APP_ID + '.svg'), icons / (APP_ID + '.svg'))
    if with_extension:
        source = ROOT / 'linux/gnome' / UUID
        metadata = json.loads((source / 'metadata.json').read_text())
        if shutil.which('gnome-shell'):
            result = subprocess.run(['gnome-shell', '--version'], capture_output=True, text=True, check=True)
            match = re.search(r'(\d+)\.', result.stdout)
            if match and match.group(1) not in metadata['shell-version']:
                raise SystemExit(f'The desktop app is installed, but GNOME {match.group(1)} is outside the extension target versions. Use Choose File or drop into its window.')
        extensions = base / 'gnome-shell/extensions' / UUID
        shutil.copytree(source, extensions, dirs_exist_ok=True)
        print('GNOME extension installed. Log out and back in once, then enable it:')
        print(f'  gnome-extensions enable {UUID}')
    print(f'ShiftDrop installed: {launcher}')
    print('Open ShiftDrop from Applications, or run: ~/.local/bin/shiftdrop')
    print('For scanned PDFs and image-to-text: install tesseract-ocr (Ubuntu) or tesseract (Fedora).')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--no-gnome-extension', action='store_true', help='Install only the app, e.g. on an X11 desktop')
    options = parser.parse_args()
    install(with_extension=not options.no_gnome_extension)
