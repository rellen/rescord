{
  # Rescord as a Nix package and a NixOS module (ADR 0044):
  #
  #   nix build github:rellen/rescord
  #
  # and in the flake of a NixOS machine:
  #
  #   inputs.rescord.url = "github:rellen/rescord";
  #   modules = [ rescord.nixosModules.default { services.rescord = { ... }; } ];
  #
  # nixpkgs is the one of devenv, so the package has the Erlang and the
  # Elixir that the tests ran on.
  description = "Rescord, a management system for animal rescues and refuges";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forEachSystem = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Erlang/OTP 29 and Elixir 1.20, as in devenv.nix.
      beamPackagesOf =
        pkgs: pkgs.beam.packages.erlang_29.overrideScope (_final: prev: { elixir = prev.elixir_1_20; });
    in
    {
      packages = forEachSystem (pkgs: rec {
        rescord = pkgs.callPackage ./nix/package.nix { beamPackages = beamPackagesOf pkgs; };
        default = rescord;
      });

      nixosModules = rec {
        rescord = import ./nix/module.nix self;
        default = rescord;
      };

      checks = forEachSystem (pkgs: {
        package = self.packages.${pkgs.stdenv.hostPlatform.system}.rescord;
        # A machine with the module: Rescord starts, migrates, and answers
        # its health check. It needs KVM to run in reasonable time.
        module = pkgs.testers.runNixOSTest (import ./nix/test.nix self);
      });

      formatter = forEachSystem (pkgs: pkgs.nixfmt-rfc-style);
    };
}
