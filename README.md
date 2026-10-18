<p align="center">
  <img src="linux/resources/io.github.shiftdrop.ShiftDrop.svg" width="96" alt="ShiftDrop icon">
</p>

# ShiftDrop

**Your files. One gesture.** Free, open-source file conversions for **macOS, Windows, and Linux**.



https://github.com/user-attachments/assets/61562337-a528-4a51-aeb3-0ae893153d35



Drag a file, press **Shift**, and drop it onto a format in the translucent radial menu. Release and press **Shift again** during the same drag to switch to seven image tools. Conversions run locally, and outputs are saved as separate copies beside the original.

[Get started](#get-started) · [Formats and tools](#formats-and-tools) · [Contribute](CONTRIBUTING.md) · [MIT license](LICENSE)

> **Experimental and untested:** Nix packages, the NixOS module, and the Hyprland 0.56.2 companion have not completed build and end-to-end validation. They are available for testing, not presented as verified platform support. See [experimental NixOS / Hyprland setup](docs/HYPRLAND.md).

## What works today

- **macOS:** native Swift menu bar app, confirmed working on a physical Mac.
- **Windows:** shared desktop app, confirmed working on a physical Windows machine. The global gesture targets File Explorer and the desktop.
- **Linux / GNOME Wayland:** shared desktop app with a GNOME Shell companion. The complete drag, Shift, second-Shift toggle, and copy-drop flow passed an automated GNOME 46.2 Wayland test. Physical Linux desktop testing is still needed.
- **Other Linux desktops:** an X11 adapter is implemented but needs desktop validation. KDE Wayland has no global gesture companion; use Choose File or drop into the app window.
- **Nix / NixOS / Hyprland:** experimental and untested. The Hyprland companion currently targets 0.56.2 only and requires an exact compositor/package match.

No account, conversion server, or subscription is required. Originals and existing outputs are preserved. The native Mac app uses Swift/AppKit/SwiftUI; Windows and Linux share a Python/Qt app.

## Get started

Clone the source when following the installation or build instructions:

```sh
git clone https://github.com/zepredos/ShiftDrop.git
cd ShiftDrop
```

Development binaries are also available as artifacts of successful [Desktop tests and packages runs](https://github.com/zepredos/ShiftDrop/actions/workflows/desktop.yml). Artifact downloads require a GitHub account. There is no tagged stable release yet.

### macOS

Download and extract the **ShiftDrop-macOS** artifact, then open `ShiftDrop.app`. Or build locally with macOS 14+, Apple Command Line Tools / Swift 5.9+, and Homebrew:

```sh
brew install webp
bash scripts/build-app.sh
open dist/ShiftDrop.app
```

The app runs in the menu bar. Current packaged builds target Apple Silicon and use a local development signature; they are not Developer ID signed or notarized. See [Mac setup, features, and limits](docs/MACOS.md).

### Windows

Download the **ShiftDrop-Windows** artifact and extract it, then extract the `ShiftDrop-0.2.0-windows-*.zip` inside. Keep the extracted folder together and open `ShiftDrop\ShiftDrop.exe`. For a Start menu shortcut, double-click `scripts\install-windows.cmd`.

The binary includes Python and the conversion libraries. For a source checkout, install **Python 3.11 or newer** (3.12 recommended), then double-click the same installer. If running PowerShell directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\install-windows.ps1"
```

The installer applies the execution-policy setting only to that process; it does not change the saved policy or require administrator access. Organization-enforced policies can still take precedence. OCR requires local Tesseract in `PATH`.

### Linux: GNOME on Wayland

Install Python 3.11+ and your distribution's runtime libraries, then run the user-local installer.

Ubuntu 24.04 or newer:

```sh
sudo apt install python3-venv libegl1 libopengl0 libxcb-cursor0 libxkbcommon0 tesseract-ocr
python3 scripts/install-linux.py
```

Fedora with GNOME:

```sh
sudo dnf install python3 python3-pip mesa-libEGL mesa-libGL libxkbcommon tesseract tesseract-langpack-eng
python3 scripts/install-linux.py
```

After the first extension installation, log out and back in, then enable it:

```sh
gnome-extensions enable shiftdrop@local.shiftdrop
```

Open **ShiftDrop** from Applications or its GNOME panel icon. The app can also activate through D-Bus when the extension detects a file drag + Shift. The companion reads drag state and MIME types; native Qt drag-and-drop supplies files and accepts a copy.

GNOME 46–51 are API targets; automated end-to-end validation currently covers GNOME 46.2. On X11, install with `--no-gnome-extension`. See [Linux setup and desktop checks](docs/LINUX.md).

### Nix / NixOS / Hyprland — experimental, untested

The repository includes a flake, a NixOS module, and a companion for **Hyprland 0.56.2**. The module is designed to build the companion against your existing `config.programs.hyprland.package`; Hyprland can stay in `configuration.nix` rather than Home Manager.

These paths have **not been validated on a NixOS machine**. The initial full integration run was stopped while compiling Hyprland; plugin loading and the complete Hyprland gesture have not passed end-to-end testing. Routine CI checks syntax and isolated gesture logic only. The expensive package/compositor/VM test remains **manual and opt-in**.

Use the [experimental NixOS and Hyprland guide](docs/HYPRLAND.md) if you want to help test. Fedora/Hyprland is experimental too.

## Formats and tools

- **PDF:** JPG/PNG pages at 300 dpi, TXT, and DOCX; pages are processed individually.
- **Images:** JPG, PNG, WebP, HEIC, TIFF, AVIF, BMP, PDF, and DOCX through local OCR.
- **Text / Markdown / RTF / DOCX:** PDF, DOCX, TXT, and PNG. Plain text inputs must be UTF-8.
- **Seven image tools:** compress, metadata inspection, edit, annotate, add background, crop, and redact.
- **Editing:** brightness, contrast, saturation, rotation, flip, crop ratios and dimensions, background presets/custom colors, padding, corners, and shadows.

Editors save separate copies. Redactions are flattened into pixels and exports discard input metadata. DOCX output contains reflowed text rather than the original page layout. Editors handle one image at a time; animated images use their first frame. Image-to-text and scanned PDF exports need local OCR. Codec availability and image limits vary by platform; see the platform guides. Audio, video, and archive conversion are outside the current scope.

## Development and validation

```sh
python3 -m venv .venv
# Linux / macOS; use .venv\Scripts\python.exe on Windows:
.venv/bin/python -m pip install -c constraints.txt -e ".[dev]"
.venv/bin/python -m shiftdrop
.venv/bin/python -m pytest -q
node --test linux/tests/gesture.test.mjs
```

Native Mac checks use `bash scripts/test.sh`. The desktop workflow tests Linux and Windows, builds their native packages, checks frozen-app startup, tests the native Mac app, and exercises a real GNOME Wayland file drag. [Run 39146536652](https://github.com/zepredos/ShiftDrop/actions/runs/39146536652) passed all four desktop jobs. Mac and Windows were also confirmed working on physical desktops on 2026-10-18.

The separate [Hyprland checks workflow](https://github.com/zepredos/ShiftDrop/actions/workflows/hyprland.yml) keeps normal checks lightweight. A passing quick check does **not** establish working NixOS or Hyprland support. Detailed editor, cancellation, display-scaling, multi-monitor, and broader Linux desktop checks remain.

## Packaging

Build on the target OS; PyInstaller does not cross-compile native binaries from macOS:

```sh
python scripts/package-portable.py
```

This creates a Linux `.tar.gz` or Windows ZIP containing the app and installer. GNOME and clean source archives can be packaged separately:

```sh
python scripts/package-portable.py --extension-only
python scripts/package-source.py
```

No GitHub release is published automatically. See [release checklist](docs/PUBLISHING.md) and [contributor instructions](CONTRIBUTING.md). Launch video projects and reference recordings are kept outside the repository.

## License

ShiftDrop's original code is available under the [MIT License](LICENSE). Third-party libraries and codecs retain their own licenses; see [third-party components and notices](THIRD_PARTY_NOTICES.md).
