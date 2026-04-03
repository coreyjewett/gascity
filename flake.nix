{
  description = "Gas City — orchestration-builder SDK for multi-agent systems";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      version = "0.13.4";

      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f {
            pkgs = nixpkgs.legacyPackages.${system};
            inherit system self;
          }
        );
    in
    {
      packages = forAllSystems (
        { pkgs, ... }:
        let
          gc = pkgs.callPackage ./contrib/nix/package.nix {
            inherit version;
            src = self;
          };
        in
        {
          default = gc;
          gascity = gc;
        }
      );

      # Explicit apps output — what `nix run` resolves to
      apps = forAllSystems (
        { self, system, ... }:
        {
          default = {
            type = "app";
            program = "${self.packages.${system}.default}/bin/gc";
          };
        }
      );

      # nix develop — full development environment with all runtime deps
      devShells = forAllSystems (
        { pkgs, ... }:
        {
          default = pkgs.mkShell {
            packages = [
              # Build toolchain
              pkgs.go

              # Runtime deps (required — see contrib/nix/README.md)
              pkgs.tmux
              pkgs.git
              pkgs.jq
              pkgs.procps # pgrep
              pkgs.lsof

              # Beads work-tracking backend
              # Pinned versions from deps.env:
              #   DOLT_VERSION=1.85.0  BD_COMMIT=9d9d0e53
              pkgs.dolt
              pkgs.util-linux # flock
              # bd (beads CLI) not in nixpkgs — install separately:
              #   https://github.com/gastownhall/beads/releases
              # Or set GC_BEADS=file to skip the beads backend entirely.
            ];

            shellHook = ''
              echo "Gas City dev shell"
              echo "  build:   go build ./cmd/gc"
              echo "  test:    go test ./..."
              echo "  install: make install"
              echo ""
              echo "Runtime deps: tmux git jq pgrep lsof dolt flock"
              echo "bd (beads CLI) must be installed separately — see contrib/nix/README.md"
            '';
          };
        }
      );

      # home-manager module — usage: inputs.gascity.homeManagerModules.default
      homeManagerModules.default = import ./contrib/nix/hm-module.nix { inputs = { gascity = self; }; };
      homeManagerModules.gascity = import ./contrib/nix/hm-module.nix { inputs = { gascity = self; }; };

      formatter = forAllSystems ({ pkgs, ... }: pkgs.nixfmt-rfc-style);
    };
}
