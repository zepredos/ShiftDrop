# ShiftDrop for Mac

A native macOS menu bar utility: drag a file, press Shift, then drop onto a translucent circular menu. Includes the four-way PDF wheel, eight-way image wheel, seven-way image tools wheel, crop editor, and background editor.

## Run

Download and extract the **ShiftDrop-macOS** artifact from a successful [desktop workflow run](https://github.com/zepredos/ShiftDrop/actions/workflows/desktop.yml), then open `ShiftDrop.app` in Finder. Or follow the build instructions below to create `dist/ShiftDrop.app` locally. It runs in the menu bar. Current packaged builds target Apple Silicon.

1. Start dragging a file from Finder or the desktop.
2. Press **Shift** to show the format wheel at your pointer.
3. Move over a format and release the file to convert it.
4. For an image, release and press **Shift again** during the same drag to switch to the tools wheel.

Results are saved beside the source. Originals and existing files are never overwritten; duplicate names get a number. Click the completion notification to reveal the result in Finder.

The menu bar also has **Choose File…**, **How to Use**, **Reveal Last Result**, **Pause Drag + Shift**, and **Quit**. Finder’s **Open With → ShiftDrop** opens the same wheel. In a wheel, use arrow keys and Return, Tab to switch to image tools, and Escape to cancel. Clicking the center also switches image wheels.

## Conversions and tools

- **PDF:** DOCX, JPG, PNG, TXT. Every PDF page is exported at 300 dpi when converting to images, with numbered filenames. Pages are processed individually to bound memory usage.
- **Images:** PNG/JPG, WebP, HEIC, TIFF, AVIF, BMP, PDF, DOCX. DOCX uses local text recognition.
- **Text, Markdown, RTF, DOCX:** PDF, DOCX, TXT, PNG. Plain text inputs must be UTF-8.
- **Image tools:** crop, compression, metadata inspection, brightness/contrast/saturation, rotation, horizontal flip, freehand annotation, flattened black-box redaction, and backgrounds.
- **Crop:** drag eight handles or the selection, draw a fresh selection, choose an aspect ratio, or enter pixel dimensions.
- **Backgrounds:** gradient and solid presets, custom color, padding, corner radius, shadow, and Auto/1:1/16:9/4:5 canvas ratios, with a live preview.

All file processing stays on the Mac. The app does not use a server or require an account, network access, or Accessibility permission for the drag gesture.

## Build and test

Requires macOS 14+, Apple Command Line Tools with Swift 5.9+, and Homebrew WebP for packaging. AVIF encoding requires a macOS version whose ImageIO supports it; it is verified on macOS 26. Older systems show a clear error for unavailable codecs.

```sh
brew install webp
bash scripts/test.sh
bash scripts/build-app.sh
open dist/ShiftDrop.app
```

The app uses AppKit, SwiftUI, ImageIO, PDFKit, Core Image, and Vision. WebP and its SharpYUV dependency are bundled in the app with their license, so the built app does not need Homebrew installed. No Swift packages are downloaded. The build script signs the app locally and verifies the signature.

To regenerate the source-drawn app icon:

```sh
swift scripts/make-icon.swift
iconutil -c icns .reference/AppIcon.iconset -o Resources/AppIcon.icns
```

## Version 0.1 scope

This version focuses on PDF/image/document conversions and image tools. It does not include audio/video/archive converters. Pressing Shift again switches to the tools wheel. Exact blur and tint depend on the Mac’s wallpaper and transparency settings.

DOCX exports contain reflowed text and do not preserve the source document’s page layout. OCR accuracy depends on the source image. Animated images use the first frame; multipage TIFF conversion preserves its pages. Editors work on one image at a time. Metadata is inspected but not edited. Large images are limited to 12,000 pixels along the longest edge when loaded, with a 100-megapixel rendering limit.

The packaged app is an Apple Silicon development build with a local signature. App Store distribution, Developer ID signing/notarization, Intel/universal packaging, and launch-at-login are outside this first version.

## Validation

All eight automated tests pass. They cover real decoding of all seven image output codecs on this Mac, multipage PDFs, local OCR, long-document pagination, readable PDF/text/DOCX output, XML escaping, corrupt input, size limits, collision-safe output, and wheel hit regions. Native UI checks covered PDF → JPG → crop → background export, both wheels, ratio presets, and image controls. The user also confirmed that dragging a file in Finder and pressing Shift opens the wheel.
