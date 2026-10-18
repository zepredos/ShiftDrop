{ pkgs, hyprland, app, plugin }:
let
  inputClient = pkgs.callPackage ./test-input.nix { inherit hyprland; };
  python = pkgs.python3.withPackages (p: [ p.pyside6 p.pillow p.pillow-heif p.pypdfium2 p.python-docx p.reportlab p.striprtf ]);
  qtPlugins = "${pkgs.qt6.qtbase}/${pkgs.qt6.qtbase.qtPluginPrefix}:${pkgs.qt6.qtwayland}/${pkgs.qt6.qtbase.qtPluginPrefix}";
in pkgs.testers.runNixOSTest {
  name = "shiftdrop-hyprland-0562";
  nodes.machine = { ... }: {
    imports = [ ./module.nix ];
    services.shiftdrop = { enable = true; package = app; };
    programs.hyprland = { enable = true; package = hyprland; };
    hardware.graphics.enable = true;
    services.getty.autologinUser = "tester";
    users.users.tester = { isNormalUser = true; extraGroups = [ "video" "render" ]; };
    environment.systemPackages = [ hyprland app inputClient python ];
    xdg.portal.enable = pkgs.lib.mkForce false;
    system.stateVersion = "26.05";
    virtualisation = {
      cores = 2;
      memorySize = 4096;
      qemu.options = [ "-vga none -device virtio-gpu-pci" ];
    };
  };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_file("/dev/dri/renderD128")
    command = "su - tester -c '${pkgs.dbus}/bin/dbus-run-session -- env PYTHONPATH=${../portable} QT_PLUGIN_PATH=${qtPlugins} ${python}/bin/python ${../scripts/test-hyprland.py} ${plugin}/lib/libshiftdrop.so ${inputClient}/bin/shiftdrop-test-input ${../scripts/gnome-drag-fixture.py}'"
    status, output = machine.execute(command, timeout=180)
    print(output)
    assert status == 0, output
  '';
}
