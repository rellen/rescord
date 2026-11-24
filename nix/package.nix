# The package of Rescord (ADR 0044): the release of `mix release`, built
# with the Erlang and the Elixir of devenv. `mixFodDeps` fetches the
# dependencies of Mix; its hash changes with `platform/mix.lock`, and
# `nix build` prints the new one.
{
  lib,
  beamPackages,
  esbuild,
}:

let
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../platform;
    fileset = lib.fileset.unions [
      ../platform/mix.exs
      ../platform/mix.lock
      ../platform/config
      ../platform/lib
      ../platform/priv
      ../platform/assets
      ../platform/rel
    ];
  };

  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "rescord-deps";
    inherit version src;
    hash = "sha256-kjJabzRs2opCZBUGaQNhwyIB9QKBp83QiHmYyQj6g7A=";
  };
in
beamPackages.mixRelease {
  pname = "rescord";
  inherit version src mixFodDeps;

  # The esbuild of nixpkgs: the one that the esbuild of Hex would download
  # does not run here (ADR 0001).
  env.MIX_ESBUILD_PATH = lib.getExe esbuild;

  # The assets go into the release, with their digests.
  postBuild = ''
    mix do deps.loadpaths --no-deps-check, assets.deploy
  '';

  meta = {
    description = "A management system for animal rescues and refuges";
    mainProgram = "rescord";
    platforms = lib.platforms.linux;
  };
}
