# Release checklist

ShiftDrop's source is published at [zepredos/ShiftDrop](https://github.com/zepredos/ShiftDrop) under the [MIT License](../LICENSE). This checklist covers binary releases and support claims. Public source availability does not mean every desktop integration has been validated.

1. Retain the MIT license and copyright notice for ShiftDrop's original code, together with applicable third-party licenses and notices.
2. Push a reviewed source tree. Exclude `.reference`, videos, downloaded user images, `.venv`, `.build`, local caches, and `dist`. The source packaging script uses an explicit allowlist for the same reason.
3. Native Linux/Windows tests, packaging, and frozen-app startup passed in run `39138434647`; native Mac tests and packaging passed too. Repeat them for release code changes.
4. The complete drag + Shift flow passed on GNOME 46.2 in an isolated Wayland session. Complete the physical desktop checks in `LINUX.md` before expanding the supported desktop/version list.
5. Mac and Windows were confirmed working on physical desktops on 2026-10-18. Complete detailed editor, cancellation, and high-DPI checks. Keep **Nix packages, NixOS, and Hyprland experimental and untested** until their builds and complete drag flow are validated. The original full integration run was stopped while compiling Hyprland. Quick syntax/gesture checks do not validate a working NixOS package or desktop gesture. Physical NixOS/Hyprland and Fedora/Hyprland tests are still needed.
6. Review bundled Qt, Pillow/HEIF, PDFium, document, and packaging licenses. Keep required license texts and notices in distributed artifacts. See `THIRD_PARTY_NOTICES.md`.
7. Choose a controlled GNOME extension UUID and update the installer, metadata, documentation, and activation IDs together if needed. Do not publish a fake website or a namespace belonging to another project.
8. Confirm archives contain the binary, installers, documentation, and required dependency license files. Native Qt/Python libraries remain dynamically loadable.
9. Create a tagged prerelease with OS/architecture-specific assets and clear tested versions when a binary release is ready. Preserve the experimental Nix/Hyprland label in release notes and installation instructions.

The workflow deliberately builds artifacts without automatically creating a GitHub release, uploading arbitrary local files, or granting write permissions to pull-request jobs.
