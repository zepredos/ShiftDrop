from __future__ import annotations

import math
from pathlib import Path

from PySide6.QtCore import Qt, QPointF, QRectF, Signal
from PySide6.QtGui import QColor, QFont, QLinearGradient, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import QWidget, QPushButton

from .engine import detect_kind
from .model import TOOLS, formats_for, wheel_index

EMBER = QColor('#ed3d0e')
INK = QColor('#392819')


def local_files(mime) -> list[Path]:
    if not mime.hasUrls():
        return []
    paths = [Path(url.toLocalFile()) for url in mime.urls() if url.isLocalFile() and not url.host()]
    if len(paths) != len(mime.urls()):
        return []
    try:
        for path in paths:
            detect_kind(path)
    except (ValueError, OSError):
        return []
    return paths


class Wheel(QWidget):
    action = Signal(str, bool, list)

    def __init__(self):
        super().__init__(None, Qt.WindowType.Tool | Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint)
        self.setWindowTitle('ShiftDrop Wheel')
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.setFixedSize(380, 380)
        self.setAcceptDrops(True)
        self.setMouseTracking(True)
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
        self.setAccessibleName('Conversion wheel')
        self.setAccessibleDescription('Drag a file and press Shift. Press Shift again for image tools. Tab also switches wheels. Escape closes.')
        self.files = []
        self.kind = 'image'
        self.tools = False
        self.labels = formats_for('image')
        self.selected = None
        self.manual = False
        self.buttons = []
        self.set_actions()

    def set_files(self, paths):
        paths = list(paths)
        self.files = paths
        self.kind = detect_kind(paths[0]) if paths else 'image'
        if self.kind != 'image':
            self.tools = False
        self.set_actions()

    def set_actions(self):
        extension = self.files[0].suffix if self.files else ''
        self.labels = TOOLS if self.tools and self.kind == 'image' else formats_for(self.kind, extension)
        self.selected = None
        for button in self.buttons:
            button.deleteLater()
        self.buttons = []
        for index, label in enumerate(self.labels):
            angle = -math.pi / 2 + index * math.tau / len(self.labels)
            button = QPushButton('', self)
            button.setGeometry(round(190 + math.cos(angle)*114 - 40), round(190 + math.sin(angle)*114 - 25), 80, 50)
            button.setStyleSheet('background:transparent;border:0;')
            button.setAccessibleName(label)
            button.setToolTip(label)
            button.setFocusPolicy(Qt.FocusPolicy.NoFocus)
            button.clicked.connect(lambda _checked=False, i=index: self.choose(i))
            button.show()
            self.buttons.append(button)
        self.update()

    def toggle(self):
        if self.kind == 'image':
            self.tools = not self.tools
            self.set_actions()
            point = self.mapFromGlobal(self.cursor().pos())
            self.selected = wheel_index(point.x(), point.y(), len(self.labels))
            self.update()

    def choose(self, index):
        if self.files and 0 <= index < len(self.labels):
            label, tools, paths = self.labels[index], self.tools, self.files[:]
            self.hide()
            self.action.emit(label, tools, paths)

    def dragEnterEvent(self, event):
        paths = local_files(event.mimeData())
        if paths and event.possibleActions() & Qt.DropAction.CopyAction:
            if paths != self.files:
                self.set_files(paths)
            event.setDropAction(Qt.DropAction.CopyAction)
            event.accept()
        else:
            event.ignore()

    def dragMoveEvent(self, event):
        self.selected = wheel_index(event.position().x(), event.position().y(), len(self.labels))
        self.update()
        if self.selected is not None and event.possibleActions() & Qt.DropAction.CopyAction:
            event.setDropAction(Qt.DropAction.CopyAction)
            event.accept()
        else:
            event.ignore()

    def dragLeaveEvent(self, event):
        self.selected = None
        self.update()

    def dropEvent(self, event):
        paths = local_files(event.mimeData())
        index = wheel_index(event.position().x(), event.position().y(), len(self.labels))
        if not paths or index is None or not event.possibleActions() & Qt.DropAction.CopyAction:
            event.ignore()
            return
        self.files = paths
        # Never accept a move: Shift normally requests moving files in file managers.
        event.setDropAction(Qt.DropAction.CopyAction)
        event.accept()
        self.choose(index)

    def mouseMoveEvent(self, event):
        self.selected = wheel_index(event.position().x(), event.position().y(), len(self.labels))
        self.update()

    def mousePressEvent(self, event):
        if event.button() != Qt.MouseButton.LeftButton:
            return
        point = event.position()
        if math.hypot(point.x()-190, point.y()-190) < 60:
            self.toggle()
        else:
            index = wheel_index(point.x(), point.y(), len(self.labels))
            if index is None:
                self.hide()
            else:
                self.choose(index)

    def keyPressEvent(self, event):
        key = event.key()
        if key == Qt.Key.Key_Escape:
            self.hide()
        elif key in (Qt.Key.Key_Tab, Qt.Key.Key_Shift) and not event.isAutoRepeat():
            self.toggle()
        elif key in (Qt.Key.Key_Left, Qt.Key.Key_Up):
            self.selected = ((self.selected if self.selected is not None else 0) - 1) % len(self.labels)
        elif key in (Qt.Key.Key_Right, Qt.Key.Key_Down):
            self.selected = ((self.selected if self.selected is not None else -1) + 1) % len(self.labels)
        elif key in (Qt.Key.Key_Enter, Qt.Key.Key_Return) and self.selected is not None:
            self.choose(self.selected)
        else:
            super().keyPressEvent(event)
        self.update()

    @staticmethod
    def polar(radius, angle):
        return QPointF(190 + math.cos(angle)*radius, 190 + math.sin(angle)*radius)

    def petal(self, middle):
        step = math.tau / len(self.labels)
        start, end = middle-step/2+.014, middle+step/2-.014
        outer, inner, corner = 164, 66, 10
        path = QPainterPath(self.polar(outer, start+corner/outer))
        for index in range(1, 33):
            path.lineTo(self.polar(outer, start+corner/outer+(end-start-2*corner/outer)*index/32))
        path.quadTo(self.polar(outer, end), self.polar(outer-corner, end))
        path.lineTo(self.polar(inner+corner, end))
        path.quadTo(self.polar(inner, end), self.polar(inner, end-corner/inner))
        for index in range(1, 25):
            path.lineTo(self.polar(inner, end-corner/inner-(end-start-2*corner/inner)*index/24))
        path.quadTo(self.polar(inner, start), self.polar(inner+corner, start))
        path.lineTo(self.polar(outer-corner, start))
        path.quadTo(self.polar(outer, start), self.polar(outer, start+corner/outer))
        path.closeSubpath()
        return path

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.setBrush(QColor(155, 132, 103, 105)); painter.setPen(QPen(QColor(255, 255, 255, 175), 1))
        painter.drawEllipse(QRectF(21, 21, 338, 338))
        for index, label in enumerate(self.labels):
            middle = -math.pi/2 + index*math.tau/len(self.labels)
            path = self.petal(middle)
            gradient = QLinearGradient(0, 20, 380, 380)
            gradient.setColorAt(0, QColor('#fc5010') if index == self.selected else QColor(255, 245, 211, 210))
            gradient.setColorAt(1, QColor('#dc2e07') if index == self.selected else QColor(255, 219, 196, 200))
            painter.setBrush(gradient); painter.setPen(QPen(QColor(255, 255, 255, 90), .7)); painter.drawPath(path)
            point = self.polar(114, middle)
            color = QColor('white') if index == self.selected else INK
            painter.setPen(color)
            if self.tools:
                draw_tool_icon(painter, label, point.x(), point.y()-9, color)
            painter.setFont(QFont('Sans Serif', 8 if self.tools else 10, QFont.Weight.Bold if self.tools else QFont.Weight.DemiBold))
            painter.drawText(QRectF(point.x()-48, point.y()+(6 if self.tools else -12), 96, 24), Qt.AlignmentFlag.AlignCenter, label)
        painter.setPen(Qt.PenStyle.NoPen); painter.setBrush(QColor(255, 234, 198, 205))
        painter.drawRoundedRect(QRectF(142, 167, 96, 46), 23, 23)
        if self.selected is not None:
            label = self.labels[self.selected]
        elif len(self.files) > 1:
            label = f'{len(self.files)} FILES'
        elif self.files:
            try:
                size = self.files[0].stat().st_size
                label = f'{size/1_000_000:.1f} MB' if size >= 1_000_000 else f'{size/1000:.0f} KB'
            except OSError:
                label = 'FILE'
        else:
            label = 'DROP FILE'
        painter.setPen(INK); painter.setFont(QFont('Sans Serif', 9, QFont.Weight.DemiBold))
        painter.drawText(QRectF(142, 167, 96, 46), Qt.AlignmentFlag.AlignCenter, label)


def draw_tool_icon(painter, label, x, y, color):
    painter.save(); painter.translate(x, y)
    painter.setPen(QPen(color, 1.7, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin))
    painter.setBrush(Qt.BrushStyle.NoBrush)
    if label == 'CROP':
        painter.drawPolyline([QPointF(-6, -10), QPointF(-6, 6), QPointF(10, 6)])
        painter.drawPolyline([QPointF(-10, -6), QPointF(6, -6), QPointF(6, 10)])
    elif label == 'COMPRESS':
        for sign in (-1, 1):
            painter.drawLine(QPointF(sign*9, sign*9), QPointF(sign*2, sign*2))
            painter.drawPolyline([QPointF(sign*2, sign*7), QPointF(sign*2, sign*2), QPointF(sign*7, sign*2)])
    elif label == 'METADATA':
        path = QPainterPath(QPointF(-9, -2)); path.lineTo(1, -11); path.lineTo(10, -11); path.lineTo(10, -2); path.lineTo(1, 8); path.closeSubpath()
        painter.drawPath(path); painter.drawEllipse(QPointF(6, -7), 1, 1)
    elif label == 'EDIT':
        for row, handle in [(-7, 4), (0, -4), (7, 2)]:
            painter.drawLine(-10, row, 10, row); painter.setBrush(color); painter.drawEllipse(QPointF(handle, row), 2, 2); painter.setBrush(Qt.BrushStyle.NoBrush)
    elif label == 'ADD BG':
        painter.drawRect(QRectF(-10, -8, 20, 16)); painter.drawEllipse(QPointF(-4, -2), 2, 2)
        painter.drawPolyline([QPointF(-9, 7), QPointF(1, -2), QPointF(9, 6)])
    elif label == 'ANNOTATE':
        painter.drawEllipse(QRectF(-10, -10, 20, 20)); painter.drawLine(-5, 5, 10, -10); painter.drawPolyline([QPointF(-6, 6), QPointF(-5, 1), QPointF(-1, 5), QPointF(-6, 6)])
    elif label == 'REDACT':
        path = QPainterPath(QPointF(-11, 0)); path.quadTo(0, -14, 11, 0); path.quadTo(0, 14, -11, 0)
        painter.drawPath(path); painter.drawEllipse(QRectF(-4, -4, 8, 8)); painter.drawLine(-11, -10, 11, 10)
    painter.restore()
