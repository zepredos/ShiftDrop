# Hyprland 0.56.2

ShiftDrop has an experimental Hyprland companion for the same drag + Shift wheel and second-Shift tool toggle. It runs inside the compositor to detect drag state and place the Qt wheel without taking keyboard focus. The app receives native file drops and requests a copy.

The companion targets **Hyprland 0.56.2 only** and must be built with the exact running Hyprland package and compiler. It rejects a mismatched compositor build. Physical NixOS and Fedora desktops still need validation; see the private repository's Hyprland workflow for automated build and VM results.

Normal CI checks gesture logic and Nix syntax without building the compositor. The full compositor/package/VM job is opt-in: run **Hyprland checks** manually with **integration** enabled. Its first source build can take a long time. The initial integration run was stopped during the compositor build; plugin loading and the complete Hyprland gesture are not yet validated.

## NixOS with a flake and configuration.nix

Keep your existing Hyprland configuration in `configuration.nix`; Home Manager does not need to manage Hyprland. Add ShiftDrop to your system flake's inputs:

```nix
inputs.shiftdrop.url = "git+ssh://git@github.com/zepredos/ShiftDrop";
```

The repository is currently private, so the account fetching this input needs access. Add its module to your existing `nixosSystem.modules` list, preserving your current modules:

```nix
modules = [
  inputs.shiftdrop.nixosModules.default
  ./configuration.nix
];
```

The example accesses the flake arguments through `inputs`, as in `outputs = inputs@{ self, nixpkgs, ... }: { ... };`. In `configuration.nix`, add:

```nix
services.shiftdrop.enable = true;
```

Your existing `programs.hyprland.enable = true;` and package selection stay in place. The module builds the companion against `config.programs.hyprland.package`, including a package you selected from your own Hyprland input. Do not substitute a plugin built against ShiftDrop's standalone flake package: it may have a different ABI.

Rebuild using your usual `nixos-rebuild switch --flake ...` command. If this rebuild changed Hyprland, log out and back in before loading the companion. In a terminal inside your Hyprland session, run:

```sh
shiftdrop-hyprland-start
```

The command loads the matching companion and starts the background app. If plugin permission enforcement is enabled, allow this trusted plugin through your existing Hyprland permission setup. A load failure stops the launcher and reports the mismatch rather than starting with a missing gesture.

For automatic startup, add one line to the Hyprland config you already use. With legacy `hyprland.conf` syntax:

```ini
exec-once = shiftdrop-hyprland-start
```

With Lua configuration, use your existing startup handler or add:

```lua
hl.on("hyprland.start", function()
  hl.exec_cmd("shiftdrop-hyprland-start")
end)
```

Only use the form matching your current config. The NixOS module installs the launcher; it does not rewrite your Hyprland config.

## Fedora / other distributions

Install the app with `python3 scripts/install-linux.py --no-gnome-extension`. Build the companion against the headers, libraries, and compiler used for your installed Hyprland 0.56.2:

```sh
cmake -S linux/hyprland -B build/hyprland -DCMAKE_BUILD_TYPE=Release
cmake --build build/hyprland
hyprctl plugin load "$PWD/build/hyprland/libshiftdrop.so"
~/.local/bin/shiftdrop --background
```

This needs CMake 3.30+, pkg-config, and a C++26 compiler matching Hyprland. A generic downloaded plugin binary is not interchangeable with a distribution build. Check your friend's actual `hyprctl version` before using this route. The Fedora path has not been physically validated.

## Verify the desktop gesture

1. Check `hyprctl plugin list` lists `shiftdrop`.
2. Drag a PNG from your file manager and press Shift. The wheel should appear at the pointer while the drag continues.
3. Release and press Shift again to show the seven tools; repeat to return to formats. Holding Shift should not repeatedly toggle.
4. Drop onto JPG while holding Shift. Check that a JPEG copy appears beside the original and the original remains unchanged.
5. Cancel a drag, try a PDF, and check a second monitor and your normal display scale.
6. If you loaded the companion manually, run `hyprctl plugin unload /absolute/path/to/libshiftdrop.so` with the same path to verify clean unloading.

Known limit: Hyprland's public API exposes active drag state but not the drag's offered MIME types. Shift may therefore show the wheel for a text drag too; Qt accepts local file URLs only. No raw input-device permissions are required. KDE Wayland still has no global gesture companion.
