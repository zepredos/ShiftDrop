{ lib, cmake, pkg-config, hyprland }:
hyprland.stdenv.mkDerivation {
  pname = "shiftdrop";
  version = "0.2.0";
  src = ./.;
  nativeBuildInputs = [ cmake pkg-config ];
  buildInputs = [ hyprland ] ++ hyprland.buildInputs;
  meta = {
    description = "ShiftDrop drag-and-Shift companion for Hyprland 0.56.2";
    platforms = lib.platforms.linux;
  };
}
