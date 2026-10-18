#!/usr/bin/env python3
"""Run inside the isolated NixOS VM with its virtual GPU and test input client."""

import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import time


def wait_for(check, description, timeout=30):
    end = time.monotonic() + timeout
    last = None
    while time.monotonic() < end:
        try:
            last = check()
            if last:
                return last
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            last = str(error)
        time.sleep(.1)
    raise RuntimeError(f'Timed out waiting for {description}: {last}')


def main():
    plugin, input_client, fixture = sys.argv[1:]
    processes = []
    with tempfile.TemporaryDirectory(prefix='sd-hypr-', dir='/tmp') as folder:
        base = Path(folder)
        runtime = base / 'runtime'
        runtime.mkdir(mode=0o700)
        env = {**os.environ, 'XDG_RUNTIME_DIR': str(runtime), 'XDG_SESSION_TYPE': 'wayland',
               'XDG_CURRENT_DESKTOP': 'Hyprland', 'QT_QPA_PLATFORM': 'wayland', 'LIBGL_ALWAYS_SOFTWARE': '1'}
        env.pop('WAYLAND_DISPLAY', None)
        config = base / 'test.lua'
        config.write_text('''
hl.monitor({output="", mode="1280x720@60", position="0x0", scale=1})
hl.config({animations={enabled=false}, general={gaps_in=0,gaps_out=0,border_size=0},
    misc={disable_hyprland_logo=true,force_default_wallpaper=0}, input={kb_layout="us"}})
hl.permission(".*/bin/hyprctl", "plugin", "allow")
''')
        with (base / 'hyprland.log').open('w+') as compositor_log, (base / 'app.log').open('w+') as app_log:
            try:
                compositor = subprocess.Popen(['Hyprland', '--config', str(config)], env=env,
                    stdout=compositor_log, stderr=subprocess.STDOUT)
                processes.append(compositor)
                instance = wait_for(lambda: next(iter((runtime / 'hypr').glob('*/.socket.sock')), None), 'Hyprland socket', 60)
                env['HYPRLAND_INSTANCE_SIGNATURE'] = instance.parent.name
                env['WAYLAND_DISPLAY'] = wait_for(lambda: next((p.name for p in runtime.glob('wayland-*') if not p.name.endswith('.lock')), None), 'Wayland display')

                def hypr(*arguments):
                    return subprocess.check_output(['hyprctl', *arguments], env=env, text=True, timeout=10)

                wait_for(lambda: json.loads(hypr('-j', 'monitors')), 'virtual monitor')
                print(hypr('plugin', 'load', plugin), flush=True)
                assert any(p['name'] == 'shiftdrop' for p in json.loads(hypr('-j', 'plugin', 'list')))
                app = subprocess.Popen([sys.executable, fixture, str(base)], env=env,
                    stdout=app_log, stderr=subprocess.STDOUT)
                processes.append(app)

                def state():
                    return json.loads((base / 'state.json').read_text())

                wait_for(lambda: state().get('source_size', [0])[0] > 500, 'Qt drag source')
                source = subprocess.Popen([input_client], env=env, text=True,
                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=app_log)
                processes.append(source)
                reader = selectors.DefaultSelector()
                reader.register(source.stdout, selectors.EVENT_READ)

                def response():
                    assert reader.select(10), 'Virtual input client stopped responding'
                    return source.stdout.readline().strip()

                assert response() == 'ready'

                def input_event(command):
                    source.stdin.write(command + '\n')
                    source.stdin.flush()
                    assert response() == 'ok'
                    time.sleep(.15)

                input_event('move 640 360')
                input_event('button 272 1')
                input_event('move 680 360')
                wait_for(lambda: state().get('drag_started'), 'real Wayland drag source')
                input_event('key 42 1')
                wait_for(lambda: state().get('visible'), 'Shift wheel', 15)
                wheel = wait_for(lambda: next((w for w in json.loads(hypr('-j', 'clients')) if w['title'] == 'ShiftDrop Wheel'), None), 'wheel placement')
                assert wheel['floating'] and wheel['at'] == [490, 170], wheel
                input_event('key 42 0')
                input_event('key 42 1')
                wait_for(lambda: state().get('tools'), 'second Shift tools wheel', 15)
                input_event('key 42 0')
                input_event('key 42 1')
                wait_for(lambda: not state().get('tools'), 'return to formats', 15)
                input_event('move 680 250')
                input_event('button 272 0')
                input_event('key 42 0')
                wait_for(lambda: state().get('outputs'), 'JPEG copy conversion', 15)
                result = state()
                assert result['drop_action'] == 1, result
                output, = map(Path, result['outputs'])
                assert output.read_bytes().startswith(b'\xff\xd8')
                assert (base / 'Drag Original.png').read_bytes().startswith(b'\x89PNG')
                print(hypr('plugin', 'unload', plugin), flush=True)
                assert not any(p['name'] == 'shiftdrop' for p in json.loads(hypr('-j', 'plugin', 'list')))
                assert compositor.poll() is None
                reader.close()
                print('Hyprland 0.56.2: plugin load, real drag, Shift, second Shift, placement, JPEG copy and unload passed.', flush=True)
            finally:
                if (base / 'state.json').exists():
                    print('Final drag state:', (base / 'state.json').read_text(), flush=True)
                for process in reversed(processes):
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                for log in (compositor_log, app_log):
                    log.seek(0)
                    print(log.read(), flush=True)


if __name__ == '__main__':
    main()
