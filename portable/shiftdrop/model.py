"""Wheel layout and geometry shared by the desktop UI and its tests."""

import math

TOOLS = ("COMPRESS", "METADATA", "EDIT", "ANNOTATE", "ADD BG", "CROP", "REDACT")
PDF_FORMATS = ("DOCX", "JPG", "PNG", "TXT")
TEXT_FORMATS = ("PDF", "DOCX", "TXT", "PNG")


def formats_for(kind: str, extension: str = "") -> tuple[str, ...]:
    if kind == "pdf":
        return PDF_FORMATS
    if kind == "text":
        return TEXT_FORMATS
    return ("JPG" if extension.lower().lstrip(".") == "png" else "PNG",
            "WEBP", "HEIC", "TIFF", "AVIF", "BMP", "PDF", "DOCX")


def wheel_index(x: float, y: float, count: int, center: float = 190) -> int | None:
    dx, dy = x - center, y - center
    if count < 1 or not 60 <= math.hypot(dx, dy) <= 164:
        return None
    step = math.tau / count
    return int(((math.atan2(dy, dx) + math.pi / 2 + step / 2) % math.tau) / step) % count


class ShiftGesture:
    """One activation per drag, then one wheel switch per additional Shift press."""

    def __init__(self):
        self.active = False
        self.opened = False
        self.shift_down = False

    def update(self, *, dragging: bool, shift: bool) -> str | None:
        pressed = shift and not self.shift_down
        self.shift_down = shift
        if not dragging:
            had_wheel = self.opened
            self.active = self.opened = False
            return "hide" if had_wheel else None
        self.active = True
        if not self.opened and shift:
            self.opened = True
            return "show"
        return "toggle" if self.opened and pressed else None
