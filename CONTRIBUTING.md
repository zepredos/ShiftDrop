# Contributing

Linux GNOME Wayland is the current priority. Keep the existing native Mac app working while improving the shared desktop application.

Install the development extras with `python -m pip install -c constraints.txt -e ".[dev]"`. Run `python -m pytest -q` and `node --test linux/tests/gesture.test.mjs`. Mac changes also need `bash scripts/test.sh` on macOS.

Portable application code lives in `portable/shiftdrop`. The GNOME bridge lives in `linux/gnome/shiftdrop@local.shiftdrop`. Native Mac sources live in `Sources/ShiftDrop`. Packaging and user-local installers are in `scripts`.

File conversions must remain local and preserve originals. Never accept a move drop, overwrite an existing output, invoke a shell with a user-provided filename, or read file data in the Shell extension. PDFium work is serialized because its native API is not thread-safe. Add regression tests for changes to conversion or gesture behavior.

For desktop bugs, include OS/version, GNOME version, Wayland/X11, display scaling, format, and a minimal non-sensitive sample if needed. Do not attach personal documents, credentials, or user recordings to public reports.

This repository is still in preparation. A project license must be chosen before public contributions are accepted.
