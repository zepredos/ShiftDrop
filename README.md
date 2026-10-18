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

The extension targets GNOME 46–51 APIs. Ubuntu 24.04 with GNOME 46.2 has passed a headless Wayland test of the complete drag, Shift, second-Shift toggle, and copy-drop conversion flow. Other GNOME versions and physical desktop configurations still need validation. See [Linux setup and smoke test](docs/LINUX.md).

## Windows

Extract the entire Windows binary ZIP, then open `ShiftDrop\ShiftDrop.exe` to run immediately. For a Start menu shortcut, double-click `scripts\install-windows.cmd`.

On GitHub Actions, download the **ShiftDrop-Windows** artifact under a successful run. Extract that download, then extract the `ShiftDrop-0.2.0-windows-*.zip` inside it. The compiled build includes Python and its conversion libraries; your installed Python version does not matter. GitHub's source-code ZIP requires a separate Python installation.

For a source checkout, install Python 3.11 or newer and double-click the same launcher. To run the PowerShell installer directly, open PowerShell in the extracted project folder and use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\install-windows.ps1"
```

If the source installer reports Python 3.10 or older, install Python 3.12 (including its launcher), open a new terminal, and rerun it. The installer checks the selected interpreter before creating its environment.

The launcher applies its execution-policy setting only to the installer process and does not change your saved policy or require administrator access. An organization-enforced PowerShell policy can still take precedence; use the binary directly if permitted, or ask your administrator.

Open ShiftDrop from the Start menu. Drag + Shift is detected for File Explorer and the desktop. Choose File and dropping into ShiftDrop's window also work. OCR requires Tesseract in `PATH`. The conversion/UI suite, native packaging, and frozen-app startup check pass on the Windows 2025 runner. The user has confirmed the app works on a physical Windows desktop; detailed cancellation, editor, and display-scaling checks remain.

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

GitHub Actions runs tests and builds native Linux, Windows, and Mac artifacts in the private validation repository. Portable packages must pass a frozen-app startup check before being archived. A separate headless GNOME Wayland job loads and unloads the extension and exercises the Qt D-Bus bridge. Nothing is automatically published as a public release.

## Validation and release status

The portable suite has 29 shared tests covering conversion, offscreen Qt UI, and Linux installation, plus three Windows-only installer checks. Two additional tests exercise the GNOME drag state machine. The native Mac app retains its eight tests. Coverage includes real codec decoding, PDF/text/DOCX export, multi-page rollback on failure, output collisions, copy drop semantics, editor layouts, aspect ratios, flattened redaction, launcher paths containing spaces, Python version validation, and process-scoped PowerShell policy handling. Linux and Windows packages must also pass a frozen-app startup check.

The source is in the private [zepredos/ShiftDrop validation repository](https://github.com/zepredos/ShiftDrop). [Validation run 39138434647](https://github.com/zepredos/ShiftDrop/actions/runs/39138434647) passed all four jobs: Linux tests/package/startup, Windows tests/package/startup, native Mac tests/package, and the complete GNOME Wayland drag flow. The user confirmed the app works on Mac and Windows on 2026-10-18. Available physical Linux test machines run NixOS/Hyprland and Fedora/Hyprland; their global drag gesture is not implemented yet. Detailed desktop checks, licensing, and public publication remain release gates. See [Linux scope](docs/LINUX.md), [release checklist](docs/PUBLISHING.md), and [contributor instructions](CONTRIBUTING.md).
