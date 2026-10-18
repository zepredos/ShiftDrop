#!/usr/bin/env python3
"""Catch missing modules and Qt plugins by launching the frozen app offscreen."""

import os
from pathlib import Path
import subprocess
import sys
import time


def main():
    executable = Path(sys.argv[1]).resolve()
    process = subprocess.Popen([str(executable), '--background'],
        env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen'})
    try:
        time.sleep(3)
        assert process.poll() is None, f'Packaged app exited with status {process.returncode}'
        if sys.platform == 'linux':
            for method, arguments in [('ShowWheel', ['640', '360', 'false']),
                                      ('ToggleWheel', []), ('HideWheel', [])]:
                subprocess.run(['gdbus', 'call', '--session', '--dest', 'io.github.shiftdrop.ShiftDrop',
                    '--object-path', '/io/github/shiftdrop/ShiftDrop',
                    '--method', 'io.github.shiftdrop.ShiftDrop.' + method, *arguments], check=True, timeout=10)
        print('Frozen desktop app started successfully.')
    finally:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


if __name__ == '__main__':
    main()
