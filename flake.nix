{
  description = "DFeed - D news aggregator, newsgroup client, web newsreader and IRC bot";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    self.submodules = true;
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Helper to download compressors
        htmlcompressor = pkgs.fetchurl {
          url = "https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/htmlcompressor/htmlcompressor-1.5.3.jar";
          sha256 = "1ydh1hqndnvw0d8kws5339mj6qn2yhjd8djih27423nv1hrlx2c8";
        };

        yuicompressor = pkgs.fetchurl {
          url = "https://github.com/yui/yuicompressor/releases/download/v2.4.8/yuicompressor-2.4.8.jar";
          sha256 = "1qjxlak9hbl9zd3dl5ks0w4zx5z64wjsbk7ic73r1r45fasisdrh";
        };

      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "dfeed";
          version = "unstable";

          src = ./.;

          # Don't strip debug symbols (we build with -g)
          dontStrip = true;

          nativeBuildInputs = with pkgs; [
            dmd
            dtools  # Provides rdmd
            dub
            jre_minimal  # For htmlcompressor and yuicompressor
            gnumake
            git
            which
          ];

          buildInputs = with pkgs; [
            curl
            sqlite
            openssl
          ];

          # Setup build environment
          preConfigure = ''
            # Make compressors available
            # htmlcompressor with --compress-css expects yuicompressor.jar to be
            # in the same directory as htmlcompressor.jar, so we can't just symlink
            # to read-only Nix store paths
            cp ${htmlcompressor} htmlcompressor-1.5.3.jar
            cp ${yuicompressor} yuicompressor-2.4.8.jar
          '';

          buildPhase = ''
            runHook preBuild

            # Set rdmd to use dmd by default
            export DCOMPILER=dmd

            # Detect OpenSSL version (like in the original rebuild script)
            if [ -f lib/deimos-openssl/scripts/generate_version.d ]; then
              echo "Generating OpenSSL version detection..."
              rdmd --compiler=dmd lib/deimos-openssl/scripts/generate_version.d
            fi

            # Set up D compiler flags
            flags=(
              -m64
              -g
              -Isrc
              -Ilib
              -L-lcurl
              -L-lsqlite3
              -L-lssl
              -L-lcrypto
            )

            # Add version flag for OpenSSL auto-detection
            if [ -f lib/deimos-openssl/scripts/generate_version.d ]; then
              flags+=(-version=DeimosOpenSSLAutoDetect)
            fi

            # Build config/groups.ini first (needed by make)
            echo "Generating config/groups.ini..."
            (cd config && rdmd --compiler=dmd gengroups)

            # Build all programs
            for fn in src/dfeed/progs/*.d; do
              name=$(basename "$fn" .d)
              echo "Building $name..."
              rdmd --compiler=dmd --build-only -of"$name" "''${flags[@]}" "$fn"
            done

            # Build resources
            echo "Building resources..."
            make -s

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin
            mkdir -p $out/share/dfeed

            # Install binaries
            for prog in dfeed nntpdownload sendspamfeedback unban; do
              if [ -f "$prog" ]; then
                install -Dm755 "$prog" $out/bin/"$prog"
              fi
            done

            # Install resources and configuration
            cp -r web $out/share/dfeed/
            cp -r config $out/share/dfeed/

            # Install any other necessary runtime files
            if [ -d data ]; then
              cp -r data $out/share/dfeed/
            fi

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "D news aggregator, newsgroup client, web newsreader and IRC bot";
            homepage = "https://github.com/CyberShadow/DFeed";
            license = licenses.agpl3Plus;
            platforms = platforms.linux;
            maintainers = [ ];
          };
        };

        # Development shell for working on the project
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            dmd
            dtools
            dub
            curl
            sqlite
            openssl
            jre_minimal
            gnumake
            git
          ];

          shellHook = ''
            echo "DFeed development environment"
            echo "DMD version: $(dmd --version | head -1)"
          '';
        };

        # Checks to run with 'nix flake check'
        checks = {
          # Verify that the package builds successfully
          build = self.packages.${system}.default;

          # Run D unittests
          unittests = pkgs.stdenv.mkDerivation {
            pname = "dfeed-unittests";
            version = "unstable";

            src = ./.;

            nativeBuildInputs = with pkgs; [
              dmd
              dtools
              gnumake
            ];

            buildInputs = with pkgs; [
              curl
              sqlite
              openssl
            ];

            buildPhase = ''
              runHook preBuild

              # Source Nix environment if available
              if [ -e /etc/profile.d/nix.sh ]; then
                source /etc/profile.d/nix.sh
              fi

              # Set rdmd to use dmd by default
              export DCOMPILER=dmd

              # Detect OpenSSL version
              if [ -f lib/deimos-openssl/scripts/generate_version.d ]; then
                echo "Generating OpenSSL version detection..."
                rdmd --compiler=dmd lib/deimos-openssl/scripts/generate_version.d
              fi

              # Compile library with unittests
              echo "Compiling and running unittests..."
              dmd -unittest -main -i -Isrc -Ilib -L-lcurl -L-lsqlite3 -L-lssl -L-lcrypto \
                $(find src -name "*.d" | grep -v "src/dfeed/progs/") \
                -version=DeimosOpenSSLAutoDetect \
                -od=unittest-obj -of=unittest-runner

              runHook postBuild
            '';

            checkPhase = ''
              echo "Running unittests..."
              ./unittest-runner
            '';

            installPhase = ''
              mkdir -p $out
              echo "Unittests passed" > $out/result
            '';

            doCheck = true;
          };
        };
      }
    );
}
