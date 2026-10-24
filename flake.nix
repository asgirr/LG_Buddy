{
  description = "LG Buddy: make your LG webOS TV feel at home on your Linux desktop";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      buildCommit = self.shortRev or self.dirtyShortRev or "unknown";
    in
    {
      packages = forAllSystems (pkgs: {
        lg-buddy = pkgs.callPackage ./nix/package.nix {
          src = self;
          inherit buildCommit;
        };
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.lg-buddy;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          inputsFrom = [ self.packages.${pkgs.stdenv.hostPlatform.system}.lg-buddy ];
          packages = with pkgs; [
            cargo
            rustc
            clippy
            rustfmt
            rust-analyzer
            dbus
            # GUI renderer, pointer and accessibility tests (docs/development.md)
            xvfb-run
            xdotool
            procps
            at-spi2-core
            (python3.withPackages (p: [
              p.pyatspi
              p.dbus-python
              p.pygobject3
            ]))
          ];
          env.RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
        };
      });

      checks = forAllSystems (pkgs: {
        lg-buddy = self.packages.${pkgs.stdenv.hostPlatform.system}.lg-buddy;
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
