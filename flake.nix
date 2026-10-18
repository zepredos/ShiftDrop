{
  description = "ShiftDrop — experimental, untested Nix packages and Hyprland 0.56.2 companion";
  inputs.hyprland.url = "github:hyprwm/Hyprland/v0.56.2";
  inputs.nixpkgs.follows = "hyprland/nixpkgs";
  inputs.glaze-src = { url = "github:stephenberry/glaze/v7.2.0"; flake = false; };
  outputs = { self, nixpkgs, hyprland, glaze-src, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      eachSystem = nixpkgs.lib.genAttrs systems;
      compositorFor = system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        hyprland.packages.${system}.hyprland.override {
          # The release's nixpkgs pin has Glaze 8, but Hyprland 0.56.2 requires 7.
          glaze-hyprland = (pkgs.glaze.override { enableSSL = false; enableInterop = false; }).overrideAttrs {
            version = "7.2.0";
            src = glaze-src;
          };
        };
      packagesFor = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          compositor = compositorFor system;
        in {
          default = pkgs.callPackage ./nix/app.nix { };
          shiftdrop = self.packages.${system}.default;
          hyprland-plugin = pkgs.callPackage ./linux/hyprland/default.nix { hyprland = compositor; };
        };
    in {
      packages = eachSystem packagesFor;
      nixosModules.default = import ./nix/module.nix;
      checks = eachSystem (system: {
        hyprland = import ./nix/test-hyprland.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          hyprland = compositorFor system;
          app = self.packages.${system}.shiftdrop;
          plugin = self.packages.${system}.hyprland-plugin;
        };
      });
      devShells = eachSystem (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in {
          default = pkgs.mkShell {
            packages = [ (compositorFor system)
              (pkgs.python3.withPackages (p: [ p.pywayland p.pyside6 p.pillow p.pillow-heif p.pypdfium2 p.python-docx p.reportlab p.striprtf ])) ];
          };
        });
    };
}
