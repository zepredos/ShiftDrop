"""Desktop gesture adapters. GNOME Wayland uses the companion Shell extension."""

import ctypes
import ctypes.util
import os
import sys

from PySide6.QtCore import QObject, QTimer, Slot
from PySide6.QtGui import QCursor

from .model import ShiftGesture

APP_ID = 'io.github.shiftdrop.ShiftDrop'
OBJECT_PATH = '/io/github/shiftdrop/ShiftDrop'


class DesktopBridge(QObject):
    def __init__(self, controller):
        super().__init__(controller)
        self.controller = controller

    @Slot(int, int, bool)
    def ShowWheel(self, x, y, tools):
        self.controller.show_wheel(x, y, tools=tools)

    @Slot()
    def ToggleWheel(self):
        if self.controller.wheel.isVisible():
            self.controller.wheel.toggle()

    @Slot()
    def HideWheel(self):
        self.controller.wheel.hide()

    @Slot()
    def Open(self):
        self.controller.welcome.show()
        self.controller.welcome.raise_()
        self.controller.welcome.activateWindow()


def register_dbus(controller):
    if sys.platform != 'linux':
        return None
    from PySide6.QtDBus import QDBusConnection
    bus = QDBusConnection.sessionBus()
    if not bus.isConnected():
        raise RuntimeError('No D-Bus session is available. Launch ShiftDrop from your desktop session.')
    bridge = DesktopBridge(controller)
    if not bus.registerObject(OBJECT_PATH, APP_ID, bridge, QDBusConnection.RegisterOption.ExportAllSlots):
        raise RuntimeError('Could not register the ShiftDrop desktop bridge: ' + bus.lastError().message())
    if not bus.registerService(APP_ID):
        raise RuntimeError('ShiftDrop is already running, or its D-Bus name is unavailable.')
    return bridge


class PollingGesture(QObject):
    def __init__(self, controller, pointer_state):
        super().__init__(controller)
        self.controller = controller
        self.pointer_state = pointer_state
        self.gesture = ShiftGesture()
        self.timer = QTimer(self); self.timer.setInterval(35); self.timer.timeout.connect(self.tick); self.timer.start()

    def tick(self):
        dragging, shift = self.pointer_state()
        action = self.gesture.update(dragging=dragging, shift=shift)
        if action == 'show':
            point = QCursor.pos(); self.controller.show_wheel(point.x(), point.y())
        elif action == 'toggle':
            self.controller.wheel.toggle()
        elif action == 'hide':
            QTimer.singleShot(180, lambda: self.controller.wheel.hide() if not self.gesture.opened and not self.controller.wheel.manual else None)


class WindowsPointer:
    def __init__(self):
        from ctypes import wintypes
        self.api = ctypes.WinDLL('user32', use_last_error=True)
        self.api.GetAsyncKeyState.argtypes = [ctypes.c_int]; self.api.GetAsyncKeyState.restype = ctypes.c_short
        self.api.GetForegroundWindow.argtypes = []; self.api.GetForegroundWindow.restype = wintypes.HWND
        self.api.GetClassNameW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]; self.api.GetClassNameW.restype = ctypes.c_int
        self.down = False; self.origin = None; self.explorer = False

    def __call__(self):
        down = bool(self.api.GetAsyncKeyState(1) & 0x8000)
        shift = bool(self.api.GetAsyncKeyState(0x10) & 0x8000)
        point = QCursor.pos()
        if down and not self.down:
            self.origin = point
            name = ctypes.create_unicode_buffer(256)
            self.api.GetClassNameW(self.api.GetForegroundWindow(), name, len(name))
            self.explorer = name.value in ('CabinetWClass','ExploreWClass','Progman','WorkerW')
        self.down = down
        moved = self.origin is not None and (point-self.origin).manhattanLength() >= 8
        return bool(down and moved and self.explorer), shift


class X11Pointer:
    def __init__(self):
        library = ctypes.util.find_library('X11')
        if not library:
            raise RuntimeError('X11 global dragging requires libX11.')
        self.api = ctypes.CDLL(library)
        self.api.XOpenDisplay.argtypes = [ctypes.c_char_p]; self.api.XOpenDisplay.restype = ctypes.c_void_p
        self.api.XDefaultRootWindow.argtypes = [ctypes.c_void_p]; self.api.XDefaultRootWindow.restype = ctypes.c_ulong
        self.api.XInternAtom.argtypes = [ctypes.c_void_p,ctypes.c_char_p,ctypes.c_int]; self.api.XInternAtom.restype = ctypes.c_ulong
        self.api.XGetSelectionOwner.argtypes = [ctypes.c_void_p,ctypes.c_ulong]; self.api.XGetSelectionOwner.restype = ctypes.c_ulong
        self.api.XQueryPointer.argtypes = [ctypes.c_void_p,ctypes.c_ulong,ctypes.POINTER(ctypes.c_ulong),ctypes.POINTER(ctypes.c_ulong),ctypes.POINTER(ctypes.c_int),ctypes.POINTER(ctypes.c_int),ctypes.POINTER(ctypes.c_int),ctypes.POINTER(ctypes.c_int),ctypes.POINTER(ctypes.c_uint)]
        self.api.XQueryPointer.restype = ctypes.c_int
        self.api.XCloseDisplay.argtypes = [ctypes.c_void_p]
        self.display = self.api.XOpenDisplay(None)
        if not self.display:
            raise RuntimeError('Could not connect to the X11 desktop.')
        self.root = self.api.XDefaultRootWindow(self.display)
        self.selection = self.api.XInternAtom(self.display,b'XdndSelection',False)

    def __call__(self):
        root,child = ctypes.c_ulong(),ctypes.c_ulong()
        rx,ry,wx,wy = (ctypes.c_int() for _ in range(4)); state = ctypes.c_uint()
        valid = self.api.XQueryPointer(self.display,self.root,ctypes.byref(root),ctypes.byref(child),ctypes.byref(rx),ctypes.byref(ry),ctypes.byref(wx),ctypes.byref(wy),ctypes.byref(state))
        owner = self.api.XGetSelectionOwner(self.display,self.selection)
        return bool(valid and owner and state.value & 256), bool(state.value & 1)

    def close(self):
        if self.display:
            self.api.XCloseDisplay(self.display); self.display = None


def gesture_adapter(controller):
    if sys.platform == 'win32':
        return PollingGesture(controller, WindowsPointer())
    if sys.platform == 'linux' and os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
        from .hyprland import HyprlandBridge
        return HyprlandBridge(controller)
    if sys.platform == 'linux' and os.environ.get('XDG_SESSION_TYPE') != 'wayland' and os.environ.get('DISPLAY'):
        pointer = X11Pointer()
        controller.application.aboutToQuit.connect(pointer.close)
        return PollingGesture(controller,pointer)
    return None
