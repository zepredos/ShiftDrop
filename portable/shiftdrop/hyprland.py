"""Receive wheel controls from the version-matched Hyprland companion plugin."""

import os
from pathlib import PurePosixPath
import re

from PySide6.QtCore import QObject, QTimer
from PySide6.QtNetwork import QLocalSocket


def socket_path(environment):
    signature = environment.get('HYPRLAND_INSTANCE_SIGNATURE', '')
    runtime = environment.get('XDG_RUNTIME_DIR', '')
    if not runtime or not PurePosixPath(runtime).is_absolute() or not re.fullmatch(r'[A-Za-z0-9_-]+', signature):
        raise ValueError('Hyprland session socket is unavailable.')
    return str(PurePosixPath(runtime) / 'hypr' / signature / '.socket2.sock')


def wheel_event(line):
    if line in (b'shiftdrop>>toggle', b'shiftdrop>>hide'):
        return (line.split(b'>>')[1].decode(),)
    match = re.fullmatch(rb'shiftdrop>>show,(-?\d{1,7}),(-?\d{1,7})', line)
    if match:
        return ('show', int(match[1]), int(match[2]))
    return None


class HyprlandBridge(QObject):
    def __init__(self, controller):
        super().__init__(controller)
        self.controller = controller
        self.path = socket_path(os.environ)
        self.buffer = bytearray()
        self.generation = 0
        self.socket = QLocalSocket(self)
        self.socket.readyRead.connect(self.read)
        self.socket.disconnected.connect(self.disconnected)
        self.socket.errorOccurred.connect(lambda _error: self.retry.start())
        self.retry = QTimer(self)
        self.retry.setSingleShot(True)
        self.retry.setInterval(1000)
        self.retry.timeout.connect(self.connect)
        self.connect()

    def connect(self):
        if self.socket.state() == QLocalSocket.LocalSocketState.UnconnectedState:
            self.socket.connectToServer(self.path)

    def disconnected(self):
        self.buffer.clear()
        self.generation += 1
        if not self.controller.wheel.manual:
            self.controller.wheel.hide()
        self.retry.start()

    def read(self):
        self.buffer.extend(bytes(self.socket.readAll()))
        if len(self.buffer) > 65536:
            self.socket.abort()
            self.buffer.clear()
            return
        while b'\n' in self.buffer:
            line, _, rest = self.buffer.partition(b'\n')
            self.buffer = bytearray(rest)
            event = wheel_event(line)
            if event:
                self.dispatch(event)

    def dispatch(self, event):
        if event[0] == 'show':
            self.generation += 1
            self.controller.show_wheel(event[1], event[2])
        elif event[0] == 'toggle':
            if self.controller.wheel.isVisible():
                self.controller.wheel.toggle()
        elif event[0] == 'hide':
            generation = self.generation
            # Let Qt accept the copy drop before removing its destination.
            QTimer.singleShot(180, lambda: self.controller.wheel.hide()
                if generation == self.generation and not self.controller.wheel.manual else None)
