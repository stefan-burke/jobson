{
  description = "Jobson service running in Podman";

  outputs = { self }: 
    let
      pkgs = import <nixpkgs> {};
      version = "1.0.0";
      
      # Build the .deb package
      jobson-deb = pkgs.stdenv.mkDerivation {
        name = "jobson-deb-${version}";
        src = self;
        
        buildInputs = with pkgs; [ fpm ];
        
        buildPhase = ''
          cd jobson-deb
          bash repackage-rails-app.sh ${version}
          bash make-deb-pkg.sh ${version}
        '';
        
        installPhase = ''
          mkdir -p $out
          cp target/jobson.deb $out/
        '';
      };
      
      # Docker image build script
      buildDockerImage = pkgs.writeScriptBin "build-jobson-image" ''
        #!${pkgs.bash}/bin/bash
        set -e
        
        # Build the .deb package
        echo "Building .deb package..."
        cd ${self}/jobson-deb
        bash repackage-rails-app.sh ${version}
        
        # Ensure target directory exists in Docker context
        mkdir -p ${self}/jobson-docker/target
        cp -f target/jobson.deb ${self}/jobson-docker/target/
        
        # Build Docker image
        echo "Building Docker image..."
        ${pkgs.podman}/bin/podman build -t jobson:latest ${self}/jobson-docker
      '';
      
    in {
      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.services.jobson;
          imageName = "jobson";
          imageTag = "latest";
          containerName = "jobson-container";
        in
        {
          options.services.jobson = {
            enable = lib.mkEnableOption "Jobson service via Podman";
            
            port = lib.mkOption {
              type = lib.types.port;
              default = 8080;
              description = "Host port to expose Jobson on";
            };

            workspaceDir = lib.mkOption {
              type = lib.types.path;
              default = "/var/lib/jobson";
              description = "Directory for Jobson workspace data";
            };
          };

          config = lib.mkIf cfg.enable {
            # Enable Podman
            virtualisation.podman = {
              enable = true;
              dockerCompat = true;
            };

            # Ensure workspace directory exists
            systemd.tmpfiles.rules = [
              "d ${cfg.workspaceDir} 0755 root root -"
            ];

            # Podman systemd service for Jobson
            systemd.services.jobson = {
              description = "Jobson application in Podman";
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                Type = "simple";
                Restart = "always";
                RestartSec = "10s";
                ExecStartPre = [
                  "${buildDockerImage}/bin/build-jobson-image"
                ];
                ExecStart = ''
                  ${pkgs.podman}/bin/podman run \
                    --rm \
                    --name ${containerName} \
                    -p ${toString cfg.port}:80 \
                    -v ${cfg.workspaceDir}:/home/jobson:Z \
                    ${imageName}:${imageTag}
                '';
                ExecStop = "${pkgs.podman}/bin/podman stop ${containerName}";
              };
            };
          };
        };

      # Development shell for building/testing locally
      devShells.x86_64-linux.default = 
        let
          build-jobson = pkgs.writeScriptBin "build-jobson" ''
            #!${pkgs.bash}/bin/bash
            set -e
            VERSION="''${1:-1.0.0}"
            
            echo "Building Jobson version $VERSION..."
            
            echo "Step 1: Building .deb package..."
            (cd jobson-deb && \
              bash repackage-rails-app.sh "$VERSION" && \
              bash make-deb-pkg.sh "$VERSION")
            
            echo "Step 2: Copying to Docker context..."
            mkdir -p jobson-docker/target
            # The deb file is created as jobson_VERSION_all.deb, rename to jobson.deb
            cp jobson-deb/target/jobson_''${VERSION}_all.deb jobson-docker/target/jobson.deb
            
            echo "Step 3: Building Docker image..."
            podman build -t jobson:latest jobson-docker/
            
            echo "Build complete! You can now run:"
            echo "  podman run --rm -p 8080:80 jobson:latest"
          '';
          
          run-jobson = pkgs.writeScriptBin "run-jobson" ''
            #!${pkgs.bash}/bin/bash
            echo "Starting Jobson container on port 8080..."
            podman run --rm -p 8080:80 jobson:latest
          '';
        in
        pkgs.mkShell {
          buildInputs = with pkgs; [
            podman
            podman-compose
            fpm
            ruby
            build-jobson
            run-jobson
            # Java development tools
            jdk17
            maven
          ];

          shellHook = ''
            echo "Jobson development environment"
            echo ""
            echo "Available commands:"
            echo "  build-jobson [version]  - Build .deb package and Docker image (default: 1.0.0)"
            echo "  run-jobson              - Run the Jobson container on port 8080"
            echo ""
            echo "Quick start: build-jobson && run-jobson"
          '';
        };
    };
}