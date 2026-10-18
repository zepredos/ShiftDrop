# Contributing

Contributions are welcome for macOS, Windows, and Linux. Keep the native Mac app and shared desktop application working. Nix/NixOS packaging and the Hyprland companion are **experimental and untested**; contributions and real desktop test reports are particularly useful there.

Install the development extras with `python -m pip install -c constraints.txt -e ".[dev]"`. Run `python -m pytest -q` and `node --test linux/tests/gesture.test.mjs`. Mac changes also need `bash scripts/test.sh` on macOS.

Portable application code lives in `portable/shiftdrop`. The GNOME bridge lives in `linux/gnome/shiftdrop@local.shiftdrop`. Native Mac sources live in `Sources/ShiftDrop`. The experimental Hyprland companion lives in `linux/hyprland`, with Nix packaging and its system module in `nix`. Packaging and user-local installers are in `scripts`.

File conversions must remain local and preserve originals. Never accept a move drop, overwrite an existing output, invoke a shell with a user-provided filename, or read file data in the Shell extension. PDFium work is serialized because its native API is not thread-safe. Add regression tests for changes to conversion or gesture behavior.

For desktop bugs, include OS/version, desktop/compositor version, Wayland/X11, display scaling, format, and a minimal non-sensitive sample if needed. For NixOS/Hyprland, also include your Hyprland package/version and relevant flake/module setup. Do not attach personal documents, credentials, or user recordings to public reports.

Normal Hyprland CI tests isolated gesture logic and parses Nix syntax. The full compositor/package/NixOS VM build is manual and opt-in; enable `integration` when running the Hyprland workflow. Do not infer working NixOS support from a passing quick check.

Keep launch videos, reference material, and generated media projects outside the repository. Do not commit local environments, build output, credentials, or private documents.

ShiftDrop's original code and contributions are licensed under the [MIT License](LICENSE). Preserve third-party notices and licenses when changing dependencies or packages.
