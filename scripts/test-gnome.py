#!/usr/bin/env python3
"""Run with system Python inside dbus-run-session on a Linux GNOME test runner."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

from gi.repository import Gio, GLib

ROOT = Path(__file__).resolve().parent.parent
UUID = 'shiftdrop@local.shiftdrop'
APP = 'io.github.shiftdrop.ShiftDrop'
BUS = Gio.bus_get_sync(Gio.BusType.SESSION, None)


def call(name, path, interface, method, signature=None, values=()):
    parameters = GLib.Variant(signature, values) if signature else None
    return BUS.call_sync(name, path, interface, method, parameters, None,
                         Gio.DBusCallFlags.NONE, 3000, None).unpack()


def wait_for(check, description):
    deadline = time.monotonic() + 60
    last = None
    while time.monotonic() < deadline:
        try:
            last = check()
            if last:
                return
        except GLib.Error as error:
            last = str(error)
        time.sleep(.5)
    raise RuntimeError(f'Timed out waiting for {description}: {last}')


def extension_info():
    return call('org.gnome.Shell', '/org/gnome/Shell', 'org.gnome.Shell.Extensions',
                'GetExtensionInfo', '(s)', (UUID,))[0]


def drag_test(directory):
    # Mutter's test session receives virtual input; the user's desktop is never involved.
    name = 'org.gnome.Mutter.RemoteDesktop'
    session, = call(name, '/org/gnome/Mutter/RemoteDesktop', name, 'CreateSession')
    interface = name + '.Session'

    def input_event(method, signature=None, values=()):
        call(name, session, interface, method, signature, values)
        time.sleep(.15)

    def state():
        path = directory / 'state.json'
        return json.loads(path.read_text()) if path.exists() else {}

    input_event('Start')
    try:
        input_event('NotifyKeyboardKeycode', '(ub)', (1, True))
        input_event('NotifyKeyboardKeycode', '(ub)', (1, False))
        time.sleep(1)
        input_event('NotifyPointerMotionRelative', '(dd)', (-10000., -10000.))
        input_event('NotifyPointerMotionRelative', '(dd)', (640., 360.))
        input_event('NotifyPointerButton', '(ib)', (272, True))
        input_event('NotifyPointerMotionRelative', '(dd)', (40., 0.))
        input_event('NotifyKeyboardKeycode', '(ub)', (42, True))
        wait_for(lambda: state().get('visible'), 'drag + Shift wheel')
        input_event('NotifyKeyboardKeycode', '(ub)', (42, False))
        input_event('NotifyKeyboardKeycode', '(ub)', (42, True))
        wait_for(lambda: state().get('tools'), 'second Shift tools wheel')
        input_event('NotifyKeyboardKeycode', '(ub)', (42, False))
        input_event('NotifyKeyboardKeycode', '(ub)', (42, True))
        wait_for(lambda: state().get('visible') and not state().get('tools'), 'conversion wheel toggle')
        input_event('NotifyPointerMotionRelative', '(dd)', (0., -110.))
        input_event('NotifyPointerButton', '(ib)', (272, False))
        input_event('NotifyKeyboardKeycode', '(ub)', (42, False))
        wait_for(lambda: state().get('outputs'), 'converted copy after real Wayland drop')
        result = state()
        assert result['drop_action'] == 1, result  # Qt.CopyAction even while Shift requests move.
        original = directory / 'Drag Original.png'
        output, = map(Path, result['outputs'])
        assert original.read_bytes().startswith(b'\x89PNG'), 'Original was changed'
        assert output != original and output.read_bytes().startswith(b'\xff\xd8'), result
        print('Real Wayland drag: Shift opened, second Shift toggled, JPEG drop copied, original preserved.')
    except BaseException:
        print('Last drag state:', state())
        raise
    finally:
        input_event('Stop')


def main():
    processes = []
    with tempfile.TemporaryDirectory(prefix='shiftdrop-gnome-') as directory:
        base = Path(directory)
        env = os.environ.copy()
        for name in ('DATA', 'CONFIG', 'CACHE', 'RUNTIME'):
            folder = base / name.lower()
            folder.mkdir(mode=0o700)
            env[f'XDG_{name}_' + ('DIR' if name == 'RUNTIME' else 'HOME')] = str(folder)
        env.update(GSETTINGS_BACKEND='keyfile', XDG_SESSION_TYPE='wayland',
                   XDG_CURRENT_DESKTOP='GNOME', GNOME_SHELL_SESSION_MODE='user',
                   LIBGL_ALWAYS_SOFTWARE='1', QT_QPA_PLATFORM='wayland', WAYLAND_DISPLAY='wayland-0')
        extension = Path(env['XDG_DATA_HOME']) / 'gnome-shell/extensions' / UUID
        shutil.copytree(ROOT / 'linux/gnome' / UUID, extension)
        subprocess.run(['gsettings', 'set', 'org.gnome.shell', 'enabled-extensions', f"['{UUID}']"], env=env, check=True)
        with (base / 'shell.log').open('w+') as shell_log, (base / 'app.log').open('w+') as app_log:
            try:
                processes.append(subprocess.Popen(['gnome-shell', '--headless', '--wayland',
                    '--virtual-monitor', '1280x720', '--no-x11', '--sm-disable'], env=env,
                    stdout=shell_log, stderr=subprocess.STDOUT))
                wait_for(lambda: extension_info().get('state') == 1, 'enabled GNOME extension')
                assert not extension_info().get('error'), extension_info()
                processes.append(subprocess.Popen([sys.argv[1], str(ROOT / 'scripts/gnome-drag-fixture.py'), str(base)],
                    cwd=ROOT, env=env, stdout=app_log, stderr=subprocess.STDOUT))
                wait_for(lambda: call('org.freedesktop.DBus', '/org/freedesktop/DBus',
                    'org.freedesktop.DBus', 'NameHasOwner', '(s)', (APP,))[0], 'desktop app D-Bus bridge')
                for method, signature, values in [('ShowWheel', '(iib)', (640, 360, False)),
                        ('ToggleWheel', None, ()), ('HideWheel', None, ())]:
                    call(APP, '/io/github/shiftdrop/ShiftDrop', APP, method, signature, values)
                assert all(process.poll() is None for process in processes), 'A desktop process exited'
                call(APP, '/io/github/shiftdrop/ShiftDrop', APP, 'HideWheel')
                drag_test(base)
                call(APP, '/io/github/shiftdrop/ShiftDrop', APP, 'Open')
                call('org.gnome.Shell', '/org/gnome/Shell', 'org.gnome.Shell.Extensions',
                     'DisableExtension', '(s)', (UUID,))
                wait_for(lambda: extension_info().get('state') == 2, 'extension cleanup')
                assert not extension_info().get('error'), extension_info()
                print('GNOME Wayland: extension enabled, Qt bridge exercised, extension disabled cleanly.')
            finally:
                for process in reversed(processes):
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                for log in (shell_log, app_log):
                    log.seek(0)
                    print(log.read())


if __name__ == '__main__':
    main()
