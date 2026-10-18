{ lib, cmake, pkg-config, hyprland }:
hyprland.stdenv.mkDerivation {
  pname = "shiftdrop";
  version = "0.2.0";
  src = ./.;
  nativeBuildInputs = [ cmake pkg-config ];
  buildInputs = [ hyprland ] ++ hyprland.buildInputs;
  meta = {
    description = "Experimental, untested ShiftDrop companion for Hyprland 0.56.2";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
