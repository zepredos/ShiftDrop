{ stdenv, pkg-config, wayland, wayland-scanner, libxkbcommon, hyprland }:
stdenv.mkDerivation {
  pname = "shiftdrop-hyprland-test-input";
  version = "0.2.0";
  src = ../linux/tests;
  nativeBuildInputs = [ pkg-config wayland-scanner ];
  buildInputs = [ wayland libxkbcommon ];
  buildPhase = ''
    wayland-scanner client-header ${hyprland.src}/protocols/virtual-keyboard-unstable-v1.xml virtual-keyboard-client.h
    wayland-scanner private-code ${hyprland.src}/protocols/virtual-keyboard-unstable-v1.xml virtual-keyboard.c
    wayland-scanner client-header ${hyprland.src}/protocols/wlr-virtual-pointer-unstable-v1.xml virtual-pointer-client.h
    wayland-scanner private-code ${hyprland.src}/protocols/wlr-virtual-pointer-unstable-v1.xml virtual-pointer.c
    cc -std=c11 hyprland-input.c virtual-keyboard.c virtual-pointer.c \
      $(pkg-config --cflags --libs wayland-client xkbcommon) -o shiftdrop-test-input
  '';
  installPhase = ''install -Dm755 shiftdrop-test-input $out/bin/shiftdrop-test-input'';
}
