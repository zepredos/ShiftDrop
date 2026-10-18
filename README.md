# ShiftDrop

Local file conversions from a translucent radial menu. Drag a file, press **Shift**, and drop onto a format. Release and press **Shift again** during the same drag to switch to image tools.

The native Mac version is retained. The new shared desktop app targets **Linux first**, specifically GNOME on Wayland, and Windows. No account or conversion server is required. Originals and existing outputs are preserved.

## Linux: GNOME on Wayland

The desktop app handles conversions, radial menus, and image editors. A companion GNOME Shell extension detects the drag + Shift gesture and places the wheel at the pointer. The extension reads drag state and MIME types, not file contents. Qt receives the file drop and accepts a **copy**, so holding Shift cannot move or delete the original.

On Ubuntu 24.04 or newer:

```sh
sudo apt install python3-venv libegl1 libopengl0 libxcb-cursor0 libxkbcommon0 tesseract-ocr
python3 scripts/install-linux.py
```

On Fedora with GNOME:

```sh
sudo dnf install python3 python3-pip mesa-libEGL mesa-libGL libxkbcommon tesseract tesseract-langpack-eng
python3 scripts/install-linux.py
```

After the first installation, log out and back in, then enable the extension:

```sh
gnome-extensions enable shiftdrop@local.shiftdrop
```

Open **ShiftDrop** from Applications, or use its GNOME panel icon. The panel icon provides access on desktops without an AppIndicator tray. The app can start automatically through D-Bus when Shift triggers a file drag. On X11, install with `--no-gnome-extension`; the app detects XDND drags directly.

The extension targets GNOME 46–51 APIs. This is an experimental port: native GNOME runtime validation is required before calling these versions supported. See [Linux setup and smoke test](docs/LINUX.md).

## Windows

For the source version, install Python 3.11 or newer, then run:

```powershell
powershell -File scripts/install-windows.ps1
```

Open ShiftDrop from the Start menu. Drag + Shift is detected for File Explorer and the desktop. Choose File and dropping into ShiftDrop's window also work. OCR requires Tesseract in `PATH`. The Windows adapter and packaging workflow need a native Windows run before release.

## Mac

Open `dist/ShiftDrop.app` for the existing native Swift app. See [Mac instructions](docs/MACOS.md). The new Python application does not replace it.

## Formats and tools

- PDF → JPG/PNG pages at 300 dpi, TXT, and DOCX. PDF pages are processed individually.
- Images → JPG, PNG, WebP, HEIC, TIFF, AVIF, BMP, PDF, and DOCX via local OCR.
- UTF-8 text, Markdown, RTF, and DOCX → PDF, DOCX, TXT, and PNG.
- Crop, compress, inspect metadata, adjust brightness/contrast/saturation, rotate, flip, annotate, redact, and add backgrounds.
- Background presets, custom colors, padding, corner radius, shadow, and canvas ratios match the Mac flow.

Editors save separate copies. Redactions are flattened into pixels and exports discard input metadata. DOCX output contains reflowed text. Animated images use their first frame. Editors work on one image at a time. Images are limited to 100 megapixels and 16,000 pixels per side. Image-to-text and scanned PDF exports require local Tesseract and its English data. Codec availability depends on the installed Pillow/HEIF wheels.

## Development

```sh
python3 -m venv .venv
# Linux / macOS:
.venv/bin/python -m pip install -c constraints.txt -e ".[dev]"
.venv/bin/python -m shiftdrop
.venv/bin/python -m pytest -q
node --test linux/tests/gesture.test.mjs
```

On Windows use `.venv/Scripts/python.exe` instead. Python 3.12 is used by the portable build workflow. The app uses Qt's essential modules, Pillow/HEIF, PDFium, python-docx, and ReportLab. There is no web renderer.

## Packaging

Run this on the target OS to build its binary and installable archive:

```sh
python scripts/package-portable.py
```

Linux produces a `.tar.gz` with a user-local installer; Windows produces a ZIP with an executable and Start menu installer. Both include their conversion libraries. PyInstaller cannot cross-compile native binaries from a Mac. The GNOME extension and a clean source archive can be packaged anywhere:

```sh
python scripts/package-portable.py --extension-only
python scripts/package-source.py
```

GitHub Actions is configured to run tests and build native Linux, Windows, and Mac artifacts. It has not yet run because this project has no GitHub remote. Nothing is automatically published as a public release.

## Validation and release status

The portable conversion and offscreen Qt UI suite has 28 passing tests on the development Mac. Two additional tests exercise the GNOME drag state machine. The native Mac app retains its eight passing tests. Coverage includes real codec decoding, PDF/text/DOCX export, multi-page rollback on failure, output collisions, copy drop semantics, editor layouts, aspect ratios, and flattened redaction.

GNOME Wayland drag placement and File Explorer dragging require native desktop smoke tests. The project is being prepared for GitHub; licensing, native CI results, and public publication are the next release gates. See [release checklist](docs/PUBLISHING.md) and [contributor instructions](CONTRIBUTING.md).
