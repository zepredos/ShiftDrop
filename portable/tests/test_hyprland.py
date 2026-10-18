from pathlib import Path
import os
import tempfile

import pytest
from PySide6.QtCore import QObject
from PySide6.QtNetwork import QLocalServer
from PySide6.QtTest import QTest

from shiftdrop.hyprland import HyprlandBridge, socket_path, wheel_event
from shiftdrop.wheel import Wheel


def test_hyprland_socket_and_message_validation():
    assert socket_path({'XDG_RUNTIME_DIR': '/run/user/1000', 'HYPRLAND_INSTANCE_SIGNATURE': 'abc_123'}) == '/run/user/1000/hypr/abc_123/.socket2.sock'
    for signature in ('', '../other', '/tmp/socket', 'bad\nname'):
        with pytest.raises(ValueError):
            socket_path({'XDG_RUNTIME_DIR': '/run/user/1000', 'HYPRLAND_INSTANCE_SIGNATURE': signature})
    assert wheel_event(b'shiftdrop>>show,-1920,540') == ('show', -1920, 540)
    assert wheel_event(b'shiftdrop>>toggle') == ('toggle',)
    for line in (b'openwindow>>data', b'shiftdrop>>show,0,0;exec bad', b'shiftdrop>>show,999999999,0', b'shiftdrop>>show,nan,0'):
        assert wheel_event(line) is None


@pytest.mark.skipif(os.name == 'nt', reason='Hyprland uses Unix domain sockets')
def test_hyprland_ipc_drives_wheel_and_preserves_new_drag(application, monkeypatch):
    # Unix socket paths must fit sockaddr_un even on macOS's long pytest temp roots.
    directory = tempfile.TemporaryDirectory(prefix='sd-', dir='/tmp')
    monkeypatch.setenv('XDG_RUNTIME_DIR', directory.name)
    monkeypatch.setenv('HYPRLAND_INSTANCE_SIGNATURE', 'test')
    path = Path(socket_path(os.environ))
    path.parent.mkdir(parents=True)
    server = QLocalServer()
    assert server.listen(str(path))

    class Controller(QObject):
        def __init__(self):
            super().__init__()
            self.wheel = Wheel()
            self.shown = []

        def show_wheel(self, x, y):
            self.shown.append((x, y))
            self.wheel.manual = False
            self.wheel.show()

    controller = Controller()
    bridge = HyprlandBridge(controller)
    try:
        QTest.qWait(30)
        assert server.hasPendingConnections()
        peer = server.nextPendingConnection()
        peer.write(b'activewindow>>ignore\nshiftdrop>>sho')
        peer.flush()
        QTest.qWait(20)
        assert controller.shown == []
        peer.write(b'w,-100,540\nshiftdrop>>toggle\n')
        peer.flush()
        QTest.qWait(40)
        assert controller.shown == [(-100, 540)]
        assert controller.wheel.tools
        peer.write(b'shiftdrop>>hide\nshiftdrop>>show,100,200\n')
        peer.flush()
        QTest.qWait(220)
        assert controller.wheel.isVisible()
        peer.write(b'shiftdrop>>hide\n')
        peer.flush()
        QTest.qWait(220)
        assert not controller.wheel.isVisible()
        controller.wheel.manual = True
        controller.wheel.show()
        peer.disconnectFromServer()
        QTest.qWait(30)
        assert controller.wheel.isVisible()
    finally:
        bridge.retry.stop()
        bridge.socket.abort()
        bridge.retry.stop()
        controller.wheel.close()
        server.close()
        directory.cleanup()
