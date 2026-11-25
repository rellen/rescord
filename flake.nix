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
  # nixpkgs is the one of devenv, so the package has the Elixir that the
  # tests ran on. Its Erlang/OTP can be a security release ahead of
  # nixpkgs (ADR 0053).
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

      # Erlang/OTP 29.1.3 (24 November 2026) fixes nine CVEs, among them a
      # buffer overrun and two crashes of binary_to_term (ADR 0053). nixpkgs
      # has 29.1.2, so the package builds 29.1.3 from its source. The override
      # does nothing once nixpkgs has 29.1.3 or later: take it out then.
      otp = "29.1.3";
      withOtp =
        pkgs: erlang:
        if pkgs.lib.versionAtLeast erlang.version otp then
          erlang
        else
          erlang.overrideAttrs (_old: {
            version = otp;
            src = pkgs.fetchgit {
              name = "otp-${otp}-source";
              url = "https://github.com/erlang/otp.git";
              rev = "refs/tags/OTP-${otp}";
              hash = "sha256-1jnaYBKpbO6EpSrhOfeRdpUsn5n+HD+YXrzt8TbIGns=";
            };
          });

      # Erlang/OTP 29 and Elixir 1.20, as in devenv.nix.
      beamPackagesOf =
        pkgs:
        pkgs.beam.packages.erlang_29.overrideScope (
          _final: prev: {
            erlang = withOtp pkgs prev.erlang;
            elixir = prev.elixir_1_20;
          }
        );
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
