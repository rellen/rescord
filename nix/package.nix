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

  # The emails (ADR 0070): `mjml` has a native library too, the MJML
  # compiler, and the build of a template runs it. It comes here in the same
  # way. The version is the one of `mjml` in `platform/mix.lock`, and each
  # hash is the one that `checksum-Elixir.Mjml.Native.exs` of that package
  # gives for the name.
  mjmlNative = rec {
    version = "5.3.1";
    name = "libmjml_nif-v${version}-nif-2.16-${mdexNative.target}.so.tar.gz";
    file = fetchurl {
      url = "https://github.com/adoptoposs/mjml_nif/releases/download/v${version}/${name}";
      hash =
        {
          x86_64-linux = "sha256-VV/ZTNHkhc0A6umjl+KRS99Mv6Jrs1KNyLjeWMVyLfA=";
          aarch64-linux = "sha256-cFfmHBFTmK67PNx6eKJ/REHrO3i63c15Iu1AxLy410Q=";
        }
        .${stdenv.hostPlatform.system};
    };
  };

  # The reports (ADR 0076): `ash_typst` has a native library too, the Typst
  # compiler. It comes here in the same way. The version is the one of
  # `ash_typst` in `platform/mix.lock`, and each hash is the one that
  # `checksum-Elixir.AshTypst.NIF.exs` of that package gives for the name.
  typstNative = rec {
    version = "0.6.1";
    name = "libtypst_nif-v${version}-nif-2.17-${mdexNative.target}.so.tar.gz";
    file = fetchurl {
      url = "https://github.com/frankdugan3/ash_typst/releases/download/v${version}/${name}";
      hash =
        {
          x86_64-linux = "sha256-deq/piR+v1ELoOFFgfyQWjZ6piJXDQJl31EjmtkwB50=";
          aarch64-linux = "sha256-PCVKsFb0cbaGLsRJWXz6pjzPvlejN3BSWy/LuDr9fdc=";
        }
        .${stdenv.hostPlatform.system};
    };
  };

  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "rescord-deps";
    inherit version src;
    hash = "sha256-VF2Ws0Cl0k67wr7i3n7FRAcheuR1t8XE9kkVqw52CSU=";
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
    cp ${mjmlNative.file} "$RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH/${mjmlNative.name}"
    cp ${typstNative.file} "$RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH/${typstNative.name}"
  '';

  # The assets go into the release, with their digests.
  postBuild = ''
    mix do deps.loadpaths --no-deps-check, assets.deploy
  '';

  # The library of MDEx was built for a system with its C library in a
  # usual place. Here it gets the path of the C library of the package. The
  # libraries of mjml and of Typst also name `libgcc_s`, which is beside the
  # C++ library.
  postInstall = ''
    patchelf --set-rpath ${lib.makeLibraryPath [ stdenv.cc.libc ]} \
      $out/lib/mdex_native-*/priv/native/*.so
    patchelf --set-rpath ${
      lib.makeLibraryPath [
        stdenv.cc.libc
        stdenv.cc.cc.lib
      ]
    } \
      $out/lib/mjml-*/priv/native/*.so $out/lib/ash_typst-*/priv/native/*.so
  '';

  meta = {
    description = "A management system for animal rescues and refuges";
    mainProgram = "rescord";
    platforms = lib.platforms.linux;
  };
}
