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

        # Helper to download compressors (for minification)
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

          src = self;

          # Don't strip debug symbols (we build with -g)
          dontStrip = true;

          nativeBuildInputs = with pkgs; [
            dmd
            dtools  # Provides rdmd
            jre_minimal  # For htmlcompressor and yuicompressor
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
            cp ${htmlcompressor} htmlcompressor-1.5.3.jar
            cp ${yuicompressor} yuicompressor-2.4.8.jar
          '';

          buildPhase = ''
            runHook preBuild

            # Set rdmd to use dmd by default
            export DCOMPILER=dmd

            # Detect OpenSSL version
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

            # Build all programs
            for fn in src/dfeed/progs/*.d; do
              name=$(basename "$fn" .d)
              echo "Building $name..."
              rdmd --compiler=dmd --build-only -of"$name" "''${flags[@]}" "$fn"
            done

            # Minify site-defaults resources (if not already minified)
            HTMLTOOL="java -jar htmlcompressor-1.5.3.jar --compress-css"
            JSTOOL="java -jar yuicompressor-2.4.8.jar --type js"
            CSSTOOL="java -jar yuicompressor-2.4.8.jar --type css"

            for htt in site-defaults/web/*.htt; do
              min="''${htt%.htt}.min.htt"
              if [ ! -f "$min" ] || [ "$htt" -nt "$min" ]; then
                echo "Minifying $htt..."
                $HTMLTOOL < "$htt" > "$min" || cp "$htt" "$min"
              fi
            done

            for css in site-defaults/web/static/css/*.css; do
              [[ "$css" == *.min.css ]] && continue
              min="''${css%.css}.min.css"
              if [ ! -f "$min" ] || [ "$css" -nt "$min" ]; then
                echo "Minifying $css..."
                $CSSTOOL < "$css" > "$min" || cp "$css" "$min"
              fi
            done

            for js in site-defaults/web/static/js/*.js; do
              [[ "$js" == *.min.js ]] && continue
              min="''${js%.js}.min.js"
              if [ ! -f "$min" ] || [ "$js" -nt "$min" ]; then
                echo "Minifying $js..."
                $JSTOOL < "$js" > "$min" || cp "$js" "$min"
              fi
            done

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

            # Install site-defaults (generic resources)
            cp -r site-defaults $out/share/dfeed/

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

          # Run Playwright end-to-end tests
          playwright = pkgs.stdenv.mkDerivation {
            pname = "dfeed-playwright-tests";
            version = "unstable";

            src = self;

            nativeBuildInputs = with pkgs; [
              playwright-test
              curl
              sqlite
            ];

            # Playwright needs writable home for cache
            HOME = "/tmp/playwright-home";

            buildPhase = ''
              runHook preBuild

              # Create test environment
              mkdir -p site/config/apis data/db

              # Create minimal site.ini
              cat > site/config/site.ini << 'SITEINI'
              name = DFeed Test Instance
              host = localhost
              proto = http
              SITEINI

              # Create web.ini with test port
              cat > site/config/web.ini << 'WEBINI'
              [listen]
              port = 8080
              WEBINI

              # Disable StopForumSpam in sandbox (no network access)
              cat > site/config/apis/stopforumspam.ini << 'SPAMINI'
              enabled = false
              SPAMINI

              # Configure user authentication with a test salt
              cat > site/config/user.ini << 'USERINI'
              salt = test-salt-for-playwright-tests-only
              USERINI

              # Configure test group with dummy captcha and disabled rate limiting for testing
              cat > site/config/groups.ini << 'GROUPSINI'
              [sets.test]
              name=Test
              shortName=Test
              visible=true

              [groups.test]
              internalName=test
              publicName=Test Forum
              navName=Test
              urlName=test
              groupSet=test
              description=A test forum for trying out posting
              sinkType=local
              announce=false
              captcha=dummy
              postThrottleRejectCount=0
              postThrottleCaptchaCount=0
              GROUPSINI

              # Database is automatically created and migrated by dfeed

              # Start dfeed server in background
              ${self.packages.${system}.default}/bin/dfeed --no-sources &
              DFEED_PID=$!

              # Wait for server to be ready (up to 30 seconds)
              echo "Waiting for DFeed server to start..."
              for i in $(seq 1 30); do
                if curl -s http://localhost:8080/ > /dev/null 2>&1; then
                  echo "Server is ready!"
                  break
                fi
                if ! kill -0 $DFEED_PID 2>/dev/null; then
                  echo "Server process died unexpectedly"
                  exit 1
                fi
                sleep 1
              done

              # Verify server is actually responding
              if ! curl -s http://localhost:8080/ > /dev/null 2>&1; then
                echo "Server failed to start within 30 seconds"
                kill $DFEED_PID 2>/dev/null || true
                exit 1
              fi

              # Run Playwright tests
              cd tests
              playwright test --reporter=list || TEST_RESULT=$?
              cd ..

              # Stop server
              kill $DFEED_PID 2>/dev/null || true
              wait $DFEED_PID 2>/dev/null || true

              # Check test result
              if [ "''${TEST_RESULT:-0}" != "0" ]; then
                echo "Playwright tests failed"
                exit 1
              fi

              runHook postBuild
            '';

            installPhase = ''
              mkdir -p $out
              echo "Playwright tests passed" > $out/result
            '';
          };

          # Run D unittests
          unittests = pkgs.stdenv.mkDerivation {
            pname = "dfeed-unittests";
            version = "unstable";

            src = self;

            nativeBuildInputs = with pkgs; [
              dmd
              dtools
            ];

            buildInputs = with pkgs; [
              curl
              sqlite
              openssl
            ];

            buildPhase = ''
              runHook preBuild

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
