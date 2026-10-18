# GitHub publication checklist

The project has not been published. The requested order is Linux first, then Windows validation, then a public open-source release.

1. Choose the GitHub repository name/account and approve a project license. Add its full text and correct copyright holder before calling the project open source.
2. Push a reviewed source tree. Exclude `.reference`, videos, downloaded user images, `.venv`, `.build`, local caches, and `dist`. The source packaging script uses an explicit allowlist for the same reason.
3. Run `.github/workflows/desktop.yml` on native Linux and Windows runners. Inspect test results and test the packaged binaries, not only source checkouts.
4. Complete the GNOME Wayland smoke test in `LINUX.md`. The Shell extension is experimental until a real GNOME session passes it.
5. Complete File Explorer drag/drop, second Shift, editor, cancellation, and high-DPI checks on Windows.
6. Review bundled Qt, Pillow/HEIF, PDFium, document, and packaging licenses. Keep required license texts and notices in distributed artifacts. See `THIRD_PARTY_NOTICES.md`.
7. Choose a controlled GNOME extension UUID and update the installer, metadata, documentation, and activation IDs together if needed. Do not publish a fake website or a namespace belonging to another project.
8. Confirm archives contain the binary, installers, documentation, and required dependency license files. Native Qt/Python libraries remain dynamically loadable.
9. Create a tagged prerelease with OS/architecture-specific assets and clear tested versions. Make the repository public only when that is authorized.

The workflow deliberately builds artifacts without automatically creating a GitHub release, uploading arbitrary local files, or granting write permissions to pull-request jobs.
