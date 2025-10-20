{
  description = "All dependencies required for eclipse openbsw";

  inputs = {
    devenv-root = {
      url = "file+file:///dev/null";
      flake = false;
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs_25_05.url = "github:NixOS/nixpkgs/nixos-25.05";
    devenv.url = "github:cachix/devenv";
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";
    treefmt.url = "github:numtide/treefmt/v2.1.0";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = { nixpkgs.follows = "nixpkgs"; };
    };
  };

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = inputs@{ flake-parts, devenv-root, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.devenv.flakeModule
      ];
      systems = [ "x86_64-linux" "i686-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      perSystem = { config, self', inputs', pkgs, system, ... }: {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        devenv.shells.default = {
          devenv.root =
            let
              devenvRootFileContent = builtins.readFile devenv-root.outPath;
            in
            pkgs.lib.mkIf (devenvRootFileContent != "") devenvRootFileContent;

          name = "open-bsw";

          imports = [
            # This is just like the imports in devenv.nix.
            # See https://devenv.sh/guides/using-with-flake-parts/#import-a-devenv-module
            # ./devenv-foo.nix
          ];

          languages.rust = {
            enable = true;
            channel = "stable";
            targets = [ "thumbv7em-none-eabihf" ];
          };

          languages.python = {
            enable = true;
            venv = {
              enable = true;
            };
          };

          # https://devenv.sh/reference/options/
          packages = with pkgs; [
            cmake
            ninja
            gnumake
            gcc-arm-embedded
            gcc
            (import inputs.nixpkgs_25_05 {inherit system;}).llvmPackages_17.clang-tools
            llvmPackages_19.clang#-unwrapped
            libcxx
            minicom
            inputs.treefmt.packages."${system}".default
            black
            cmake-format
            ccache
            can-utils

            # Documentation build
            (python3.withPackages (p: [
              p.sphinx
              p.sphinxcontrib-jquery
              p.sphinxcontrib-plantuml
              p.sphinx-copybutton
              p.pyyaml
              p.sphinx-rtd-theme
              p.pillow
              (p.buildPythonPackage rec {
                pname = "dox_style";
                version = "0.2.1";
                src = fetchPypi {
                  inherit pname version;
                  hash = "sha256-4lY3wVQD0mRooc0rr+6BVZyaiDd34g3rd3wFHmEIlDI=";
                };
                prePatch = ''
                  substituteInPlace pyproject.toml \
                    --replace-fail " >= 70.0.0" ""
                '';
                build-system = [ p.setuptools ];
                pyproject = true;
              })
              (p.buildPythonPackage rec {
                pname = "dox_util";
                version = "0.1.0";
                src = fetchPypi {
                  inherit pname version;
                  hash = "sha256-iuFeR633Zmwbpg2Zga29CU8Mjq+s9461l9v7VZyQ/qY=";
                };
                prePatch = ''
                substituteInPlace pyproject.toml \
                    --replace-fail " >= 70.0.0" ""
                '';
                build-system = [ p.setuptools ];
                pyproject = true;
              })
              (p.buildPythonPackage rec {
                pname = "dox_trace";
                version = "3.0.0";
                src = fetchPypi {
                  inherit pname version;
                  hash = "sha256-hZSTnrjk8EoLbnNWpt2j9z8SwW36JD1OuPVwqsY3OwU=";
                };
                prePatch = ''
                substituteInPlace pyproject.toml \
                    --replace-fail " >= 70.0.0" ""
                '';
                build-system = [ p.setuptools ];
                pyproject = true;
              })
            ]))
            plantuml
            
            pkgs.gdb
            (pkgs.callPackage ./nix/gdb-server.nix { })

            # rust
            rust-cbindgen
            rust-bindgen
          ];

          env.CMAKE_CXX_COMPILER_LAUNCHER = "ccache";
          env.LIBCLANG_PATH = "${pkgs.llvmPackages_19.libclang.lib}/lib";

          scripts.gdb-server.exec = ''
            # TODO: document how to add udev rules
            pegdbserver_console -device=NXP_S32K1xx_S32K148F2M0M11 -startserver -serverport=7224 -gdbmiport=6224 -interface=OPENSDA -s8
          '';
          scripts.bsw-flash-s32k1.exec = ''
            # gdb-server &
            # sleep 1
            gdb -batch \
              -ex 'file build/s32k148-gcc/executables/referenceApp/application/RelWithDebInfo/app.referenceApp.elf' \
              -ex 'target remote localhost:7224' \
              -ex 'load'
            wait
          '';
          scripts.bsw-connect-serial.exec = ''
            ${pkgs.minicom}/bin/minicom -R utf8 -D /dev/serial/by-id/usb-P_E_Microcomputer_Systems_Inc._OpenSDA_Hardware_SDAFDB36E1B-if00 -b 115200
          '';
          # scripts.verify.exec = ''
          #   treefmt

          #   rm -rf cmake-build-*

          #   cmake -B cmake-build-unit-tests -S executables/unitTest -DBUILD_UNIT_TESTS=ON -DCMAKE_BUILD_TYPE=Debug
          #   cmake --build cmake-build-unit-tests -j
          #   ctest --test-dir cmake-build-unit-tests -j

          #   cmake -B cmake-build-posix -S executables/referenceApp
          #   cmake --build cmake-build-posix --target app.referenceApp -j

          #   cmake -B cmake-build-s32k148 -S executables/referenceApp -DBUILD_TARGET_PLATFORM="S32K148EVB" --toolchain ../../admin/cmake/ArmNoneEabi.cmake
          #   cmake --build cmake-build-s32k148 --target app.referenceApp -j
          # '';
        };


      };
      flake = {
        # The usual flake attributes can be defined here, including system-
        # agnostic ones like nixosModule and system-enumerating ones, although
        # those are more easily expressed in perSystem.

      };
    };
}
