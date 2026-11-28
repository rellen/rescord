# The package of Rescord (ADR 0044): the release of `mix release`, built
# with the Erlang and the Elixir of devenv. `mixFodDeps` fetches the
# dependencies of Mix; its hash changes with `platform/mix.lock`, and
# `nix build` prints the new one.
{
  lib,
  beamPackages,
  esbuild,
  vips,
  pkg-config,
  fetchurl,
  stdenv,
  patchelf,
}:

let
  # The version of `platform/mix.exs`, its one home (ADR 0060): the line
  # `version: "X.Y.Z",` of `project/0`.
  version = builtins.head (
    builtins.match ".*\n +version: \"([^\"]+)\",\n.*" (builtins.readFile ../platform/mix.exs)
  );

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

  # The Markdown of an answer of Ruby: MDEx has a native library, and its
  # package downloads a build of it when it compiles. The build here has no
  # network, so the file comes from the release of `mdex_native` on GitHub,
  # and goes where `rustler_precompiled` looks before it downloads. The
  # version is the one of `mdex_native` in `platform/mix.lock`, and each
  # hash is the one that the file `checksum-Elixir.MDExNative.Native.exs`
  # of that package gives for the name, as `nix hash convert` writes it.
  mdexNative = rec {
    version = "0.3.4";
    target =
      {
        x86_64-linux = "x86_64-unknown-linux-gnu";
        aarch64-linux = "aarch64-unknown-linux-gnu";
      }
      .${stdenv.hostPlatform.system};
    name = "libmdex_native_nif-v${version}-nif-2.15-${target}.so.tar.gz";
    file = fetchurl {
      url = "https://github.com/leandrocp/mdex_native/releases/download/v${version}/${name}";
      hash =
        {
          x86_64-linux = "sha256-vAJHdvSk0jeD/YzRXODfQbXiUvGhpqUMQNSsnGMw7Vg=";
          aarch64-linux = "sha256-l0IdiAQ+dJBlCGYXh2G7BsuQmVtDm0e14NAEsaaWslM=";
        }
        .${stdenv.hostPlatform.system};
    };
  };

  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "rescord-deps";
    inherit version src;
    hash = "sha256-d2Tt72+7TXQfFGhWe4cSyf2/6kN45kwDNFN6mAQD2Bs=";
  };
in
beamPackages.mixRelease {
  pname = "rescord";
  inherit version src mixFodDeps;

  # The esbuild of nixpkgs: the one that the esbuild of Hex would download
  # does not run here (ADR 0001).
  env.MIX_ESBUILD_PATH = lib.getExe esbuild;

  # The photos (ADR 0055): vix builds its NIF against the libvips of
  # nixpkgs, which it finds with pkg-config. The precompiled libvips that it
  # downloads by default cannot reach the build, which has no network.
  env.VIX_COMPILATION_MODE = "PLATFORM_PROVIDED_LIBVIPS";
  nativeBuildInputs = [
    pkg-config
    patchelf
  ];
  buildInputs = [ vips ];

  preConfigure = ''
    export RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH="$TMPDIR/rustler"
    mkdir -p "$RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH"
    cp ${mdexNative.file} "$RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH/${mdexNative.name}"
  '';

  # The assets go into the release, with their digests.
  postBuild = ''
    mix do deps.loadpaths --no-deps-check, assets.deploy
  '';

  # The library of MDEx was built for a system with its C library in a
  # usual place. Here it gets the path of the C library of the package.
  postInstall = ''
    patchelf --set-rpath ${lib.makeLibraryPath [ stdenv.cc.libc ]} \
      $out/lib/mdex_native-*/priv/native/*.so
  '';

  meta = {
    description = "A management system for animal rescues and refuges";
    mainProgram = "rescord";
    platforms = lib.platforms.linux;
  };
}
