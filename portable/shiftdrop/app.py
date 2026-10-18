from __future__ import annotations

import argparse
import getpass
import json
import os
import sys
from pathlib import Path

from PySide6.QtCore import Qt, QObject, QTimer, QRunnable, QThreadPool, Signal, QUrl
from PySide6.QtGui import QIcon, QPixmap, QPainter, QColor, QDesktopServices, QAction
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtWidgets import QApplication, QLabel, QPushButton, QHBoxLayout, QFileDialog, QMessageBox, QSystemTrayIcon, QMenu

from . import __version__
from .engine import convert, detect_kind, load_image, encode, save_copy, EXTENSIONS
from .editor import Editor, GlassWindow
from .integration import APP_ID, register_dbus, gesture_adapter
from .wheel import Wheel, local_files


class WorkerSignals(QObject):
    finished = Signal(object,str)


class Worker(QRunnable):
    def __init__(self, work):
        super().__init__(); self.work = work; self.signals = WorkerSignals()

    def run(self):
        try: result,error = self.work(),''
        except Exception as failure: result,error = [],str(failure) or type(failure).__name__
        self.signals.finished.emit(result,error)


class Welcome(GlassWindow):
    def __init__(self,controller):
        super().__init__('ShiftDrop',434)
        self.controller=controller; self.setAcceptDrops(True)
        title=QLabel('A little shift. A new format.'); title.setStyleSheet('font-size:23px;font-weight:600;'); title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.layout.addStretch(); self.layout.addWidget(title); self.layout.addSpacing(16)
        message=QLabel('Drag a file. Press Shift. Drop to convert.\n\nPress Shift again for image tools.\nYour new file appears beside the original.\nEverything happens on your computer.')
        message.setAlignment(Qt.AlignmentFlag.AlignCenter); message.setStyleSheet('line-height:150%;font-size:12px;'); self.layout.addWidget(message)
        self.layout.addSpacing(24); button=QPushButton('Choose a File…'); button.setObjectName('primary'); button.clicked.connect(controller.choose_file); self.layout.addWidget(button)
        self.layout.addSpacing(14)
        hint='GNOME Wayland: enable the companion Shell extension.\nYou can also drop a file into this window.' if sys.platform=='linux' and os.environ.get('XDG_SESSION_TYPE')=='wayland' else 'Always here in your system tray.\nYou can also drop a file into this window.'
        help_label=QLabel(hint); help_label.setAlignment(Qt.AlignmentFlag.AlignCenter); help_label.setStyleSheet('font-size:10px;color:#806b59;'); self.layout.addWidget(help_label); self.layout.addStretch()

    def dragEnterEvent(self,event):
        if local_files(event.mimeData()) and event.possibleActions() & Qt.DropAction.CopyAction:
            event.setDropAction(Qt.DropAction.CopyAction); event.accept()

    def dropEvent(self,event):
        paths=local_files(event.mimeData())
        if paths and event.possibleActions() & Qt.DropAction.CopyAction:
            event.setDropAction(Qt.DropAction.CopyAction); event.accept(); self.controller.open_files(paths)


class Toast(GlassWindow):
    def __init__(self):
        super().__init__('ShiftDrop',104)
        self.setFixedWidth(350)
        self.label=QLabel(); self.label.setWordWrap(True); self.layout.addWidget(self.label); self.layout.addStretch()
        self.setWindowFlag(Qt.WindowType.WindowStaysOnTopHint)


class Controller(QObject):
    def __init__(self,application):
        super().__init__(); self.application=application; self.busy=False; self.paused=False; self.outputs=[]
        self.pool=QThreadPool(self); self.pool.setMaxThreadCount(1)
        self.wheel=Wheel(); self.wheel.action.connect(self.perform)
        self.welcome=Welcome(self); self.toast=Toast(); self.editor=None
        self.tray=QSystemTrayIcon(self.icon(),self); self.tray.setToolTip('ShiftDrop · Drag a file + Shift')
        menu=QMenu()
        for text,callback in [('Choose File…',self.choose_file),('How to Use',self.welcome.show),('Reveal Last Result',self.reveal)]:
            action=menu.addAction(text); action.triggered.connect(callback)
        menu.addSeparator(); pause=menu.addAction('Pause Drag + Shift'); pause.setCheckable(True); pause.toggled.connect(self.pause)
        menu.addAction('Quit ShiftDrop').triggered.connect(application.quit)
        self.tray.setContextMenu(menu); self.tray.activated.connect(lambda reason: self.welcome.show() if reason==QSystemTrayIcon.ActivationReason.Trigger else None)
        self.tray.show(); self.tray_menu=menu
        self.bridge=register_dbus(self)
        self.gesture=gesture_adapter(self)
        self.hide_timer=QTimer(self); self.hide_timer.setSingleShot(True); self.hide_timer.timeout.connect(self.toast.hide)

    @staticmethod
    def icon():
        image=QPixmap(64,64); image.fill(Qt.GlobalColor.transparent)
        painter=QPainter(image); painter.setRenderHint(QPainter.RenderHint.Antialiasing); painter.setPen(Qt.PenStyle.NoPen); painter.setBrush(QColor('#ed3d0e')); painter.drawRoundedRect(3,3,58,58,14,14)
        painter.setPen(QColor('white')); font=painter.font(); font.setPixelSize(38); painter.setFont(font); painter.drawText(image.rect(),Qt.AlignmentFlag.AlignCenter,'⇧'); painter.end()
        return QIcon(image)

    def pause(self,paused):
        self.paused=paused
        if paused: self.wheel.hide()

    def choose_file(self):
        paths,_=QFileDialog.getOpenFileNames(self.welcome,'Choose images, PDFs, or text documents')
        if paths: self.open_files([Path(path) for path in paths])

    def open_files(self,paths):
        try:
            for path in paths: detect_kind(path)
            self.wheel.set_files(paths)
        except (ValueError,OSError) as error: self.error(str(error)); return
        self.welcome.hide()
        from PySide6.QtGui import QCursor
        point=QCursor.pos(); self.show_wheel(point.x(),point.y(),manual=True)

    def show_wheel(self,x,y,tools=False,manual=False):
        if self.busy or self.paused or self.editor is not None and self.editor.isVisible(): return
        if not manual: self.wheel.set_files([])
        self.wheel.manual=manual; self.wheel.tools=tools; self.wheel.set_actions()
        screen=self.application.screenAt(self.welcome.pos()) or self.application.primaryScreen()
        for candidate in self.application.screens():
            if candidate.geometry().contains(x,y): screen=candidate; break
        frame=screen.availableGeometry()
        self.wheel.move(max(frame.left(),min(x-190,frame.right()-379)),max(frame.top(),min(y-190,frame.bottom()-379)))
        self.wheel.show(); self.wheel.raise_()
        if manual: self.wheel.activateWindow(); self.wheel.setFocus()

    def perform(self,label,tools,paths):
        if self.busy: return
        if tools:
            if len(paths)!=1: self.error('Select one image at a time for editing.'); return
            try:
                self.editor=Editor(label,paths[0],load_image(paths[0])); source=paths[0]
                self.editor.saved.connect(lambda image,suffix,format_name,quality: self.run('Saving image',lambda:[save_copy(encode(image,format_name,quality),source,EXTENSIONS[format_name],suffix)]))
                self.editor.show(); self.editor.raise_(); self.editor.activateWindow()
            except Exception as error: self.error(str(error))
        else:
            def work():
                outputs=[]; failures=[]
                for path in paths:
                    try: outputs.extend(convert(path,label))
                    except Exception as error: failures.append(f'{path.name}: {error}')
                return {'outputs':outputs,'failures':failures}
            self.run('Converting to '+label,work)

    def run(self,title,work):
        if self.busy: return
        self.busy=True; self.hide_timer.stop(); self.toast.label.setText(title+'…'); self.toast.show()
        worker=Worker(work); worker.signals.finished.connect(self.finished); self.pool.start(worker)

    def finished(self,result,error):
        self.busy=False
        if error: self.error(error); return
        if isinstance(result,dict):
            self.outputs=result['outputs']
            if result['failures']:
                self.error((f'Saved {len(self.outputs)} file(s).\n\n' if self.outputs else '')+'\n'.join(result['failures'])); return
        else: self.outputs=result
        text='Saved '+self.outputs[0].name if len(self.outputs)==1 else f'Saved {len(self.outputs)} files'
        self.toast.label.setText(text+'\nBeside your original.'); self.hide_timer.start(4000)
        if self.tray.isSystemTrayAvailable(): self.tray.showMessage('ShiftDrop',text)

    def error(self,message):
        self.toast.hide(); QMessageBox.warning(self.welcome,'ShiftDrop',message)

    def reveal(self):
        if self.outputs: QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.outputs[0].parent)))


def main(argv=None):
    parser=argparse.ArgumentParser(description='ShiftDrop local file converter')
    parser.add_argument('files',nargs='*'); parser.add_argument('--background',action='store_true'); parser.add_argument('--version',action='version',version=__version__)
    options=parser.parse_args(argv)
    application=QApplication(sys.argv[:1]); application.setApplicationName('ShiftDrop'); application.setApplicationVersion(__version__)
    application.setOrganizationName('ShiftDrop'); application.setDesktopFileName(APP_ID); application.setQuitOnLastWindowClosed(False)
    name=APP_ID+'-'+getpass.getuser()
    socket=QLocalSocket(); socket.connectToServer(name)
    if socket.waitForConnected(300):
        socket.write(json.dumps(options.files).encode()); socket.waitForBytesWritten(1000); socket.disconnectFromServer(); return 0
    controller=Controller(application); application.setWindowIcon(controller.icon())
    server=QLocalServer(controller); server.setSocketOptions(QLocalServer.SocketOption.UserAccessOption)
    QLocalServer.removeServer(name)
    if not server.listen(name): raise RuntimeError('Could not start ShiftDrop: '+server.errorString())
    clients=[]
    def connected():
        client=server.nextPendingConnection(); clients.append(client); buffer=bytearray()
        def ready():
            buffer.extend(bytes(client.readAll()))
            if len(buffer)>1024*1024: client.abort(); return
            try: paths=json.loads(buffer)
            except (ValueError,UnicodeDecodeError): return
            if isinstance(paths,list) and all(isinstance(path,str) for path in paths):
                if paths: controller.open_files([Path(path) for path in paths])
                else: controller.welcome.show(); controller.welcome.raise_()
            client.disconnectFromServer()
        client.readyRead.connect(ready)
        client.disconnected.connect(lambda: (clients.remove(client),client.deleteLater()) if client in clients else None)
        if client.bytesAvailable(): ready()
    server.newConnection.connect(connected)
    if options.files: QTimer.singleShot(0,lambda:controller.open_files([Path(path) for path in options.files]))
    elif not options.background: controller.welcome.show()
    return application.exec()
