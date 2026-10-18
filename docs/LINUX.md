# Linux setup and verification

The priority target is GNOME on Wayland (Ubuntu/Fedora). Install the desktop app and its Shell extension with `python3 scripts/install-linux.py`. This writes only under the current user's `~/.local` or `XDG_DATA_HOME` and does not need sudo. Install the distribution runtime dependencies listed in the main README separately.

The installer creates an Applications entry, an icon, a D-Bus activation service, a launcher, and the companion extension. A binary archive installs its bundled app. A source checkout creates an isolated virtual environment and installs the project there. After the first extension installation, log out and in before enabling it.

## Automated validation

Ubuntu 24.04 with GNOME/Mutter 46.2 passed the headless Wayland integration job in [run 39138434647](https://github.com/zepredos/ShiftDrop/actions/runs/39138434647). It loads the extension, sends a real file drag through Wayland using virtual input, checks first Shift activation and second Shift toggling, drops onto JPEG while holding Shift, and verifies a copy action and an unchanged original. Extension disable/cleanup and the D-Bus controls are checked too. The bundled Linux executable separately passes startup and D-Bus checks.

The virtual input belongs only to the isolated CI compositor. It is not part of the shipped app or extension. Physical devices, Fedora, multiple monitors, fractional scaling, and other GNOME versions still require the checks below.

## Required checks on a GNOME desktop

1. Run `gnome-shell --version` and confirm the version is listed in the extension metadata. The current target range is 46–51; these are API targets, not a claim of completed runtime tests.
2. Run `gnome-extensions info shiftdrop@local.shiftdrop` and confirm it is enabled without errors.
3. Confirm ShiftDrop appears in Applications and its panel icon opens the app.
4. Drag an image from Files, then press Shift. Confirm that the wheel appears centered at the pointer without disrupting the drag.
5. Release and press Shift again; confirm the seven image tools appear. Repeat to return to formats. Holding Shift should never repeatedly toggle.
6. Drop the image onto a format. Confirm a readable new file appears beside the original and the original is still there.
7. Drag a PDF. Confirm the four-format wheel appears when it enters the target. Export a PDF with multiple pages and verify every numbered output.
8. Crop an image, then add a background to the crop. Verify dimensions, padding, corners, shadow, and output filenames.
9. Cancel a drag with Escape, drop outside the wheel, and drop in the center. None should convert, move, or delete a file.
10. Check 100%/200% display scaling and a second monitor, including a monitor to the left of the primary display.
11. Disable the extension. Its panel icon and timer must disappear and normal desktop dragging must continue.

For logs, use `journalctl --user -f` and filter for ShiftDrop or GNOME Shell. If the extension says the app is unavailable, check that `~/.local/share/dbus-1/services/io.github.shiftdrop.ShiftDrop.service` exists and that `~/.local/bin/shiftdrop --background` starts successfully.

## D-Bus interface

The app owns `io.github.shiftdrop.ShiftDrop` at `/io/github/shiftdrop/ShiftDrop` on the user's session bus. The exported interface has `ShowWheel(i, i, b)`, `ToggleWheel()`, `HideWheel()`, and `Open()`. It provides window controls only; it does not accept a conversion command or arbitrary shell text.

The extension polls pointer modifiers only during a drag with `text/uri-list` among its MIME types. It does not read the clipboard, transfer the selection, use input-device permissions, or access file contents. Native Qt drag-and-drop supplies file paths after the wheel is shown. GNOME places only a window whose application ID and title both match ShiftDrop.

## Other Linux desktops

X11 has a direct adapter that checks the XDND selection and Shift/mouse state. Hyprland 0.56.2 has an experimental compositor companion; see [Hyprland and NixOS setup](HYPRLAND.md). KDE Wayland and other Wayland compositors currently have no global gesture adapter; use Choose File or drop into the app window once the app is running.

The available physical Linux test targets are NixOS/Hyprland and Fedora/Hyprland. Neither has been validated. The GNOME Shell companion cannot supply their gesture. The Hyprland companion targets 0.56.2 and rejects builds that do not match the running compositor. The NixOS module uses the existing system Hyprland package. Record the output of `hyprctl version` for each target before installing its companion.

For an initial app/conversion test on Fedora/Hyprland, install with `python3 scripts/install-linux.py --no-gnome-extension`, then use Choose File or drop into the app window. The system-wide gesture additionally requires the version-matched Hyprland companion. NixOS should use the flake module instead of the user-local Python installer.

The blur and glass appearance vary with the compositor. The radial geometry, labels, controls, and orange selection styling are drawn by the app.
