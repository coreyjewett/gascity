{
  description = "Gas City — orchestration-builder SDK for multi-agent systems";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      version = "0.13.4";

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      # nix build / nix run
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          gc = pkgs.callPackage ./contrib/nix/package.nix {
            inherit version;
            src = self;
          };
        in
        {
          default = gc;
          gascity = gc;
        });

      # nix develop — full development environment with all runtime deps
      devShells = forAllSystems (system:
        let pkgs = pkgsFor system; in
        {
          default = pkgs.mkShell {
            packages = [
              # Build toolchain
              pkgs.go

              # Runtime deps (required — see README)
              pkgs.tmux
              pkgs.git
              pkgs.jq
              pkgs.procps  # pgrep
              pkgs.lsof

              # Beads work-tracking backend
              # Pinned versions from deps.env:
              #   DOLT_VERSION=1.85.0  BD_COMMIT=9d9d0e53
              pkgs.dolt
              pkgs.util-linux # flock
              # bd (beads CLI) not in nixpkgs — install separately:
              #   https://github.com/gastownhall/beads/releases
            ];

            shellHook = ''
              echo "Gas City dev shell — gc available via: go run ./cmd/gc"
              echo "Runtime deps: tmux git jq pgrep lsof dolt flock"
              echo "Install bd (beads CLI) separately if not present"
            '';
          };
        });

      # home-manager module
      homeManagerModules.default = import ./contrib/nix/hm-module.nix;
      homeManagerModules.gascity = import ./contrib/nix/hm-module.nix;

      # formatter
      formatter = forAllSystems (system: (pkgsFor system).nixfmt-rfc-style);
    };
}
