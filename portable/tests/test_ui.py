import pytest
from PIL import Image
from PySide6.QtCore import Qt, QMimeData, QPointF, QUrl
from PySide6.QtGui import QDragEnterEvent, QDropEvent
from PySide6.QtTest import QTest

from shiftdrop.editor import Editor
from shiftdrop.model import ShiftGesture, TOOLS, wheel_index
from shiftdrop.wheel import Wheel, local_files


def test_shift_drag_show_hold_toggle_and_finish():
    gesture = ShiftGesture()
    assert gesture.update(dragging=False, shift=True) is None
    assert gesture.update(dragging=True, shift=True) == 'show'
    for _ in range(20): assert gesture.update(dragging=True, shift=True) is None
    assert gesture.update(dragging=True, shift=False) is None
    assert gesture.update(dragging=True, shift=True) == 'toggle'
    assert gesture.update(dragging=True, shift=False) is None
    assert gesture.update(dragging=True, shift=True) == 'toggle'
    assert gesture.update(dragging=False, shift=False) == 'hide'
    assert gesture.update(dragging=False, shift=False) is None


def test_wheel_geometry_and_tools(application, image_file):
    wheel = Wheel(); wheel.set_files([image_file]); wheel.toggle()
    assert wheel.labels == TOOLS
    assert [button.accessibleName() for button in wheel.buttons] == list(TOOLS)
    for x, y, index in [(190, 80, 0), (300, 190, 1), (190, 300, 2), (80, 190, 3)]:
        assert wheel_index(x, y, 4) == index
    assert wheel_index(190, 190, 8) is None
    assert wheel_index(0, 0, 8) is None
    wheel.toggle(); assert wheel.labels[0] == 'JPG'
    wheel.close()


def test_drop_forces_copy_even_when_shift_requests_move(application, image_file):
    wheel = Wheel(); wheel.show(); mime = QMimeData(); mime.setUrls([QUrl.fromLocalFile(str(image_file))])
    allowed = Qt.DropAction.CopyAction | Qt.DropAction.MoveAction
    enter = QDragEnterEvent(wheel.rect().center(), allowed, mime, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.ShiftModifier)
    wheel.dragEnterEvent(enter)
    assert enter.isAccepted() and enter.dropAction() == Qt.DropAction.CopyAction
    actions = []; wheel.action.connect(lambda *args: actions.append(args))
    event = QDropEvent(QPointF(190, 80), allowed, mime, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.ShiftModifier)
    wheel.dropEvent(event)
    assert event.isAccepted() and event.dropAction() == Qt.DropAction.CopyAction
    assert len(actions) == 1 and actions[0][2] == [image_file]
    assert image_file.exists()


def test_non_copy_and_remote_drops_are_rejected(application, image_file):
    wheel = Wheel(); mime = QMimeData(); mime.setUrls([QUrl.fromLocalFile(str(image_file))])
    event = QDropEvent(QPointF(190, 80), Qt.DropAction.MoveAction, mime, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.ShiftModifier)
    wheel.dropEvent(event); assert not event.isAccepted()
    mime.setUrls([QUrl('https://example.com/private.png')]); assert local_files(mime) == []
    wheel.close()


def test_crop_editor_ratio_and_export(application, image_file):
    image = Image.open(image_file).convert('RGBA'); editor = Editor('CROP', image_file, image)
    editor.select_ratio('16:9')
    result = editor.rendered()
    assert abs(result.width/result.height - 16/9) < .03
    received = []; editor.saved.connect(lambda *args: received.append(args)); editor.save()
    assert received and received[0][1:3] == (' Cropped', 'PNG')
    editor.close()


@pytest.mark.parametrize('tool', TOOLS)
def test_all_editors_construct_and_render(application, image_file, tool):
    editor = Editor(tool, image_file, Image.open(image_file).convert('RGBA'))
    editor.show(); application.processEvents()
    assert editor.grab().width() == 460
    assert editor.rendered().width > 0
    editor.close()


def test_redaction_replaces_pixels_in_flattened_export(application, image_file):
    editor = Editor('REDACT', image_file, Image.open(image_file).convert('RGBA'))
    editor.canvas.redactions = [(0, 0, .5, .5)]
    flattened = editor.rendered()
    assert flattened.getpixel((10, 10)) == (0, 0, 0, 255)
    assert flattened.getpixel((100, 60))[:3] != (0, 0, 0)
    editor.close()
