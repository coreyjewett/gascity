# Gas City — Home Manager module.
#
# Installs gc and all runtime dependencies.
# Designed to be used via the project flake:
#
#   inputs.gascity.url = "github:gastownhall/gascity";
#
#   home-manager.sharedModules = [ inputs.gascity.homeManagerModules.default ];
#
#   programs.gascity.enable = true;
#
# Runtime dep versions pinned in deps.env:
#   DOLT_VERSION=1.85.0   BD_COMMIT=9d9d0e53   BR_VERSION=0.1.20
{ inputs, ... }:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.gascity;
  gcPkg = inputs.gascity.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  options.programs.gascity = {
    enable = lib.mkEnableOption "Gas City multi-agent orchestration system";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      gcPkg

      # Required runtime deps
      pkgs.tmux
      pkgs.git
      pkgs.jq
      pkgs.procps   # pgrep
      pkgs.lsof

      # Beads work-tracking backend
      pkgs.dolt
      pkgs.util-linux  # flock
      # bd (beads CLI) — not yet in nixpkgs; install via:
      #   https://github.com/gastownhall/beads/releases
      # Or set GC_BEADS=file to bypass the beads backend entirely.
    ];
  };
}
