# Third-party components

This is a dependency inventory for release review. It does not replace upstream license texts.

ShiftDrop's [MIT License](LICENSE) covers its original code. Third-party libraries, bundled fonts, and codecs retain their own licenses and notices. The project license does not relicense those components.

- **PySide6 Essentials / Qt:** Qt for Python and Qt libraries. Review the license texts shipped with the chosen wheels and retain the applicable Qt notices in native packages. Dependencies remain dynamically loadable.
- **Pillow:** image decoding/encoding. Its wheels contain additional image codec libraries with their own notices.
- **pillow-heif / libheif:** HEIF decoding and encoding, plus the codec libraries included by the selected wheels.
- **pypdfium2 / PDFium:** PDF parsing, rendering, and extraction. Include PDFium's bundled third-party notices in binary distributions.
- **python-docx / lxml:** DOCX documents and XML processing.
- **ReportLab:** PDF creation.
- **striprtf:** RTF text extraction.
- **Tesseract:** a separately installed local OCR program. It is not bundled by the portable package script.
- **PyInstaller:** packaging tool. Review its redistribution exception and bundled runtime notices when shipping binaries.
- **WebP / SharpYUV:** bundled only by the native Mac build, with upstream COPYING included in the app.

Upstream metadata and license directories must be audited in each native artifact before its public release. No GNOME or Qt source files have been copied into this repository; integrations call their installed APIs.
