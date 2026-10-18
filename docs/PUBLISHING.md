# GitHub publication checklist

The source is in the private `zepredos/ShiftDrop` validation repository. The requested order is Linux first, then Windows validation, then a public open-source release. Public publication has not happened.

1. Choose a project license. Add its full text and correct copyright holder before calling the project open source.
2. Push a reviewed source tree. Exclude `.reference`, videos, downloaded user images, `.venv`, `.build`, local caches, and `dist`. The source packaging script uses an explicit allowlist for the same reason.
3. Native Linux/Windows tests, packaging, and frozen-app startup passed in run `39138434647`; native Mac tests and packaging passed too. Repeat them for release code changes.
4. The complete drag + Shift flow passed on GNOME 46.2 in an isolated Wayland session. Complete the physical desktop checks in `LINUX.md` before expanding the supported desktop/version list.
5. Complete File Explorer drag/drop, second Shift, editor, cancellation, and high-DPI checks on Windows.
6. Review bundled Qt, Pillow/HEIF, PDFium, document, and packaging licenses. Keep required license texts and notices in distributed artifacts. See `THIRD_PARTY_NOTICES.md`.
7. Choose a controlled GNOME extension UUID and update the installer, metadata, documentation, and activation IDs together if needed. Do not publish a fake website or a namespace belonging to another project.
8. Confirm archives contain the binary, installers, documentation, and required dependency license files. Native Qt/Python libraries remain dynamically loadable.
9. Create a tagged prerelease with OS/architecture-specific assets and clear tested versions. Make the repository public only when that is authorized.

The workflow deliberately builds artifacts without automatically creating a GitHub release, uploading arbitrary local files, or granting write permissions to pull-request jobs.
