import importlib.util
from pathlib import Path
import shlex


def test_linux_bundle_installs_launchers_and_extension(tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location('linux_installer', Path(__file__).resolve().parents[2] / 'scripts/install-linux.py')
    installer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(installer)
    bundle = tmp_path / 'download'
    (bundle / 'ShiftDrop').mkdir(parents=True)
    (bundle / 'ShiftDrop/ShiftDrop').write_bytes(b'test executable')
    resource = bundle / 'linux/resources' / (installer.APP_ID + '.svg')
    resource.parent.mkdir(parents=True)
    resource.write_text('<svg/>')
    extension = bundle / 'linux/gnome' / installer.UUID
    extension.mkdir(parents=True)
    (extension / 'metadata.json').write_text('{"shell-version":["46"]}')
    (extension / 'extension.js').write_text('// fixture')
    home = tmp_path / 'home with spaces'
    data = home / '.local/share'
    monkeypatch.setattr(installer, 'ROOT', bundle)
    monkeypatch.setattr(installer.sys, 'platform', 'linux')
    monkeypatch.setattr(installer.shutil, 'which', lambda _: None)
    monkeypatch.setattr(Path, 'home', classmethod(lambda cls: home))
    monkeypatch.setenv('XDG_DATA_HOME', str(data))
    installer.install()
    launcher = home / '.local/bin/shiftdrop'
    assert shlex.split(launcher.read_text().splitlines()[1])[1] == str(data / 'shiftdrop/app/ShiftDrop')
    assert 'Exec=' + installer.desktop_quote(launcher) + ' %F' in (data / 'applications' / (installer.APP_ID + '.desktop')).read_text()
    assert ' --background' in (data / 'dbus-1/services' / (installer.APP_ID + '.service')).read_text()
    assert (data / 'gnome-shell/extensions' / installer.UUID / 'extension.js').read_text() == '// fixture'
    assert (data / 'shiftdrop/app/ShiftDrop').read_bytes() == b'test executable'
