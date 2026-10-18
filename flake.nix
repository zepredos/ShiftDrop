{
  description = "ShiftDrop desktop app and Hyprland 0.56.2 companion";
  inputs.hyprland.url = "github:hyprwm/Hyprland/v0.56.2";
  inputs.nixpkgs.follows = "hyprland/nixpkgs";
  outputs = { self, nixpkgs, hyprland, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      eachSystem = nixpkgs.lib.genAttrs systems;
      packagesFor = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          compositor = hyprland.packages.${system}.hyprland;
        in {
          default = pkgs.callPackage ./nix/app.nix { };
          shiftdrop = self.packages.${system}.default;
          hyprland-plugin = pkgs.callPackage ./linux/hyprland/default.nix { hyprland = compositor; };
        };
    in {
      packages = eachSystem packagesFor;
      nixosModules.default = import ./nix/module.nix;
      devShells = eachSystem (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in {
          default = pkgs.mkShell {
            packages = [ hyprland.packages.${system}.hyprland
              (pkgs.python3.withPackages (p: [ p.pywayland p.pyside6 p.pillow p.pillow-heif p.pypdfium2 p.python-docx p.reportlab p.striprtf ])) ];
          };
        });
    };
}
