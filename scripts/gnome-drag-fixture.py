#!/usr/bin/env python3
"""A real Wayland drag source and the production controller, used only by CI."""

import json
from pathlib import Path
import sys

from PIL import Image
from PySide6.QtCore import QMimeData, QTimer, Qt, QUrl
from PySide6.QtGui import QCursor, QDrag
from PySide6.QtWidgets import QApplication, QLabel

from shiftdrop.app import Controller
from shiftdrop.integration import APP_ID


application = QApplication([])
application.setApplicationName('ShiftDrop')
application.setDesktopFileName(APP_ID)
application.setQuitOnLastWindowClosed(False)
controller = Controller(application)
directory = Path(sys.argv[1])
original = directory / 'Drag Original.png'
Image.new('RGB', (120, 80), '#ff8536').save(original)
drop_action = None
drag_started = False
pressed = False


class DragSource(QLabel):
    def mousePressEvent(self, event):
        global pressed
        pressed = True
        self.origin = event.position().toPoint()

    def mouseMoveEvent(self, event):
        global drop_action, drag_started
        if not event.buttons() & Qt.MouseButton.LeftButton:
            return
        if (event.position().toPoint() - self.origin).manhattanLength() < application.startDragDistance():
            return
        mime = QMimeData()
        mime.setUrls([QUrl.fromLocalFile(str(original))])
        drag = QDrag(self)
        drag.setMimeData(mime)
        drag_started = True
        drop_action = drag.exec(Qt.DropAction.CopyAction | Qt.DropAction.MoveAction).value


source = DragSource('Drag source for the isolated GNOME test')
source.setAlignment(Qt.AlignmentFlag.AlignCenter)
source.setStyleSheet('background:#425a7a;color:white;font-size:24px;')
source.showMaximized()


def snapshot():
    cursor = QCursor.pos()
    state = {'visible': controller.wheel.isVisible(), 'tools': controller.wheel.tools,
             'outputs': [str(path) for path in controller.outputs], 'drop_action': drop_action,
             'cursor': [cursor.x(), cursor.y()], 'pressed': pressed, 'drag_started': drag_started,
             'source_active': source.isActiveWindow(), 'source_size': [source.width(), source.height()]}
    temporary = directory / 'state.tmp'
    temporary.write_text(json.dumps(state))
    temporary.replace(directory / 'state.json')


timer = QTimer()
timer.timeout.connect(snapshot)
timer.start(80)
sys.exit(application.exec())
