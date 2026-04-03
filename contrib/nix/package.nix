# Gas City — Nix package derivation.
#
# Used two ways:
#   1. From the project flake (src = self, version from flake)
#   2. From nixpkgs (src = fetchFromGitHub { ... }, version pinned there)
#
# To update for a new release:
#   - Bump version and rev in the fetchFromGitHub call (nixpkgs usage)
#   - Reset vendorHash to lib.fakeHash, run `nix build`, fill in the hash
#     from the error output.
#
# Build mirrors the Makefile `build` target:
#   go build -ldflags "..." -o bin/gc ./cmd/gc
# We replicate the ldflags rather than calling `make` because the Makefile
# uses `git describe` for VERSION, which is unavailable in the Nix sandbox.
{
  lib,
  buildGoModule,
  # When called from the project flake: src = self, version = "x.y.z"
  # When packaged for nixpkgs: pass fetchFromGitHub result as src
  src,
  version,
}:

buildGoModule {
  pname = "gascity";
  inherit src version;

  vendorHash = "sha256-Z5fI5WqPXJfKv3kB1MVLBhxdAI+knAcxa0CWlmyNzkg=";

  # Tests are integration tests requiring live dolt/beads services.
  # They cannot run in the Nix build sandbox.
  doCheck = false;

  # Mirrors Makefile LDFLAGS:
  #   -X main.version=$(VERSION)
  #   -X main.commit=$(COMMIT)
  #   -X main.date=$(BUILD_TIME)
  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  # Build only the gc binary, not genschema
  subPackages = [ "cmd/gc" ];

  meta = {
    description = "Orchestration-builder SDK for multi-agent systems";
    longDescription = ''
      Gas City provides a configurable multi-agent orchestration toolkit:
      declarative city.toml configuration, runtime providers (tmux, subprocess,
      exec, ACP, Kubernetes), beads-backed work routing, formula dispatch, and
      a controller/supervisor reconciliation loop.

      Runtime dependencies (not managed by this derivation):
        Required:  tmux, git, jq, pgrep, lsof
        Beads backend: dolt (>=1.85.0), bd/beads (>=0.61.0), flock
        Set GC_BEADS=file to skip the beads backend deps.
    '';
    homepage = "https://github.com/gastownhall/gascity";
    changelog = "https://github.com/gastownhall/gascity/releases/tag/v${version}";
    license = lib.licenses.mit;
    maintainers = [ ];
    mainProgram = "gc";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
