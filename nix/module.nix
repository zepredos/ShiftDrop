{ config, lib, pkgs, ... }:
let
  cfg = config.services.shiftdrop;
  plugin = pkgs.callPackage ../linux/hyprland/default.nix {
    hyprland = config.programs.hyprland.package;
  };
  starter = pkgs.writeShellApplication {
    name = "shiftdrop-hyprland-start";
    runtimeInputs = [ cfg.package config.programs.hyprland.package pkgs.jq ];
    text = ''
      if ! hyprctl -j plugin list | jq -e 'any(.[]; .name == "shiftdrop")' >/dev/null; then
        hyprctl plugin load ${plugin}/lib/libshiftdrop.so
        if ! hyprctl -j plugin list | jq -e 'any(.[]; .name == "shiftdrop")' >/dev/null; then
          echo "ShiftDrop plugin did not load. Check that it was built with your running Hyprland package." >&2
          exit 1
        fi
      fi
      exec shiftdrop --background
    '';
  };
in {
  options.services.shiftdrop = {
    enable = lib.mkEnableOption "ShiftDrop with the Hyprland 0.56.2 gesture companion";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./app.nix { };
      description = "ShiftDrop desktop application.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.programs.hyprland.enable;
      message = "services.shiftdrop requires programs.hyprland.enable.";
    }];
    environment.systemPackages = [ cfg.package plugin starter ];
  };
}
