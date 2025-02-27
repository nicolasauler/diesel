{
  description = "Bipa flake that provides dev_shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-parts.url = "github:hercules-ci/flake-parts";

    crane.url = "github:ipetkov/crane";
  };

  outputs = inputs @ {
    flake-parts,
    nixpkgs,
    rust-overlay,
    crane,
    ...
  }:
    (flake-parts.lib.evalFlakeModule {inherit inputs;} (
      {
        lib,
        self,
        inputs,
        ...
      }: {
        imports = [
          # ./devshells.nix
        ];

        systems = [
          "x86_64-linux"
        ];

        perSystem = {
          self',
          system,
          pkgs,
          ...
        }: let
          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain (p: p.rust-bin.selectLatestNightlyWith (toolchain: toolchain.default));
          # craneLib = (inputs.crane.mkLib pkgs).overrideToolchain (p: p.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml);

          ## src = craneLib.cleanCargoSource ./.;
          unfilteredRoot = ./.; # The original, unfiltered source
          src = lib.fileset.toSource {
            root = unfilteredRoot;
            fileset = lib.fileset.unions [
              (craneLib.fileset.commonCargoSources unfilteredRoot)
              ./migrations
              ./proto
              ./consts
              ./clients
            ];
          };

          commonArgs = {
            inherit src;
            strictDeps = true;

            buildInputs = with pkgs; [
              postgresql
              protobuf
            ];
            nativeBuildInputs = with pkgs; [
              postgresql
              protobuf
            ];

            RUSTFLAGS = "-Z threads=8";
            CARGO_PROFILE = "dev";
          };

          # Build *just* the cargo dependencies, so we can reuse
          # all of that work (e.g. via cachix) when running in CI
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
          my-crate = craneLib.buildPackage (commonArgs
            // {
              inherit cargoArtifacts;

              pname = "bipa";
              meta.mainProgram = "bipa";

              doCheck = false; # skip tests
            });
        in {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            # config.allowUnfree = true;
            overlays = [
              (import rust-overlay)
            ];
          };

          checks = {
            # Build the crate as part of `nix flake check` for convenience
            inherit my-crate;

            # Note that this is done as a separate derivation so that
            # we can block the CI if there are issues here, but not
            # prevent downstream consumers from building our crate by itself.
            my-crate-clippy = craneLib.cargoClippy (commonArgs
              // {
                inherit cargoArtifacts;
                # cargoClippyExtraArgs = "--all-targets -- --deny warnings";
                cargoClippyExtraArgs = "--all-targets";
              });
          };

          packages = {
            default = my-crate;

            cargoArtifacts = cargoArtifacts;
          };

          apps.default = {
            type = "app";
            program = my-crate;
          };

          devShells.default = craneLib.devShell {
            RUSTFLAGS = "-Zthreads=8";

            packages = with pkgs; [
              bacon
              cargo-nextest
              diesel-cli
              grpcurl
              openssl
              pkg-config
              postgresql
              mariadb
              protobuf
              python3
              sqlite
              libmysqlclient
              cmake
              ncurses
            ];
          };
        };
      }
    ))
    .config
    .flake;
}
