{
  description = "Atlas Nix configuration";

  # Nixpkgs / NixOS version to use.
  # inputs.nixpkgs.url = "nixpkgs/nixos-24.11";
  # TODO: nixos-24.11 is not currently available, and required to build some
  #       flake, so we will use this one too too avoid using two different
  #       nixpkgs versions and increasing the space usage.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
      rec {
        packages = {
          # bats-custom-libs is a custom set of Bats libraries that I use in my tests.
          bats-custom-libs = pkgs.stdenv.mkDerivation {
            name = "bats-custom-libs";
            src = ./.;
            installPhase = ''
              mkdir --parent $out/share/bats
              cp --recursive .bats/bats-* $out/share/bats
            '';
          };

          # helm-schema is a tool to generate JSON schemas based on values.yaml files.
          # NOTE: This uses a custom fork of the original project, as the original
          #       project didn't allows me to manage custom `required` fields.
          helm-schema = pkgs.buildGoModule {
            pname = "helm-schema";
            version = "unstable";
            src = pkgs.fetchFromGitHub {
              owner = "chezmoi-sh";
              repo = "helm-schema";
              rev = "main";
              hash = "sha256-PootirY9vVR3Chy6WKTTqgqzeQvJ0xNqSfyE/DTWY9I=";
            };
            vendorHash = "sha256-qKizheh9YGJFe/bNeWVG+gbmsouuNlMAaZO0DvaL1R0=";
            subPackages = [ "cmd/helm-schema" ];
          };

          # kubeconform is a fast Kubernetes manifests validator, with support for Custom Resources
          kubeconform = pkgs.buildGoModule {
            pname = "kubeconform";
            version = "v0.6.7";
            src = pkgs.fetchFromGitHub {
              owner = "yannh";
              repo = "kubeconform";
              rev = "v0.6.7";
              hash = "sha256-Yq9lJ3rSG8v/PeofkZrnO2nzEgtyB5vtNafKabp8hnQ=";
            };
            vendorHash = null;
            subPackages = [ "cmd/kubeconform" ];
          };
        };

        devShells.default =
          with packages;
          pkgs.mkShell {
            packages = [
              kubeconform
              helm-schema
              pkgs.bashInteractive
              pkgs.bats
              pkgs.chart-testing
              pkgs.commitlint
              pkgs.d2
              pkgs.devcontainer
              pkgs.docker-client
              pkgs.fzf
              pkgs.gum
              pkgs.go
              pkgs.kubernetes-helm
              pkgs.helm-docs
              pkgs.just
              pkgs.k3d
              pkgs.k9s
              pkgs.kubectl
              pkgs.lefthook
              pkgs.nil
              pkgs.nix-output-monitor
              pkgs.nixfmt-rfc-style
              pkgs.skopeo
              pkgs.trunk-io
              pkgs.yq-go
            ];

            env = {
              BATS_ROOT = "${pkgs.bats}";
              BATS_LIB_PATH = "${pkgs.bats.libraries.bats-assert}/share/bats:${pkgs.bats.libraries.bats-support}/share/bats:${pkgs.bats.libraries.bats-file}/share/bats:${bats-custom-libs}/share/bats";
            };

            installPhase = "";
          };
      }
    );
}
