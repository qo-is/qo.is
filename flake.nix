{
  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    deploy-rs.url = "github:serokell/deploy-rs";
    juice = {
      url = "github:huhu/juice";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs-unstable,
      deploy-rs,
      juice,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      domain = "qo.is";
      version = "1";
      pkgs = import nixpkgs-unstable { inherit system; };
      deployPkgs = import nixpkgs-unstable {
        inherit system;
        overlays = [
          deploy-rs.overlay
          (self: super: {
            deploy-rs = {
              inherit (pkgs) deploy-rs;
              lib = super.deploy-rs.lib;
            };
          })
        ];
      };
      preparePhase = ''
        rm -rf themes/juice
        ln -s ${juice} themes/juice
      '';
    in
    {
      formatter.${system} = pkgs.nixfmt-rfc-style;
      checks.${system}.default = pkgs.stdenv.mkDerivation {
        inherit version;
        name = "${domain}-${version}";
        buildInputs = [ pkgs.zola ];
        src = ./src;
        installPhase = ''
          set -euo pipefail
          ${preparePhase}
          zola --root . check
          mkdir $out
        '';
      };
      packages.${system}.default = pkgs.stdenv.mkDerivation {
        inherit version;
        name = "${domain}-${version}";
        buildInputs = [ pkgs.zola ];
        src = ./src;
        installPhase = ''
          ${preparePhase}
          zola --root . build --output-dir $out
        '';
      };

      deploy.nodes.lindberg-webapps = {
        hostname = "lindberg-webapps.backplane.net.qo.is";
        profiles.${domain} = {
          sshUser = "nginx-${domain}";
          path = deployPkgs.deploy-rs.lib.activate.noop self.packages.${system}.default;
          profilePath = "/var/lib/nginx-${domain}/root";
        };
      };

      apps.${system} =
        let
          zola = pkgs.writeShellScriptBin "zola" ''
            cd src
            ${preparePhase}
            ${pkgs.zola}/bin/zola --root . ''${@}
          '';
          deploy = pkgs.writeShellScriptBin "deploy" ''
            ${pkgs.deploy-rs}/bin/deploy --remote-build ''${@}
          '';
        in
        {
          default = {
            type = "app";
            program = "${zola}/bin/zola";
          };
          deploy = {
            type = "app";
            program = "${deploy}/bin/deploy";
          };
        };
    };
}
