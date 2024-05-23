{
    inputs = {
        nixpkgs.url = github:nixos/nixpkgs/23.11;
        levers = {
            url = "github:kquick/nix-levers";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        galois-flakes = {
          url = "github:GaloisInc/flakes";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        ardupilot-src = {
          url = "github:ArduPilot/ardupilot/43adaf3"; # master version; versions for following inputs mirror git submodule settings
          flake = false;
        };
        ardupilot-patches = {
          url = "./patches";
          flake = false;
        };
        empy-src = {
          url = "http://www.alcyone.com/software/empy/empy-3.3.4.tar.gz";
          flake = false;
        };
        waf-src = {
          url = "github:ArduPilot/waf/1b1625b";
          flake = false;
        };
        libcanard-src = {
          url = "github:DroneCAN/libcanard/0ae477b";
          flake = false;
        };
        mavlink-src = {
          url = "github:ArduPilot/mavlink/130a836";
          flake = false;
        };
        mavproxy-src = {
          url = "github:ardupilot/mavproxy";
          flake = false;
        };
        pymavlink-src = {
          url = "github:ArduPilot/pymavlink/4d8c4ff";
          flake = false;
        };
        googletest-src = {
          url = "github:ArduPilot/googletest/c5fed93";
          flake = false;
        };
        dronecan_dsdlc-src = {
          url = "github:DroneCAN/dronecan_dsdlc/2465ace";
            flake = false;
        };
        lwip-src = {
            url = "github:ArduPilot/lwip/143a6a5";
            flake = false;
        };
        CANBUS = {
          url = "github:GaloisInc/flake_pydronecan";
          inputs.nixpkgs.follows = "nixpkgs";
          inputs.levers.follows = "levers";
          inputs.dronecan_DSDL-src.follows = "dronecan_DSDL-src";
          inputs.pydronecan-src.follows = "pydronecan-src";
        };
        dronecan_DSDL-src = {
          url = "github:DroneCAN/DSDL/de93d9c";
          flake = false;
        };
        pydronecan-src = {
          url = "github:DroneCAN/pydronecan/1f494e9";
          flake = false;
        };
    };

    outputs = { self, nixpkgs, levers, galois-flakes
              , ardupilot-src
              , ardupilot-patches
              , empy-src
              , waf-src
              , libcanard-src
              , mavlink-src
              , mavproxy-src
              , pymavlink-src
              , googletest-src
              , dronecan_dsdlc-src
              , lwip-src
              , CANBUS
              , ... }:
    {
      apps = levers.eachSystem (s:
        {
          arduplane = {
            type = "app";
            program = "${self.packages.${s}.ardupilot-sitl}/bin/arduplane";
          };
          arducopter = {
            type = "app";
            program = "${self.packages.${s}.ardupilot-sitl}/bin/arducopter";
          };
          arducopter-heli = {
            type = "app";
            program = "${self.packages.${s}.ardupilot-sitl}/bin/arducopter-heli";
          };
          ardurover = {
            type = "app";
            program = "${self.packages.${s}.ardupilot-sitl}/bin/ardurover";
          };
          ardusub = {
            type = "app";
            program = "${self.packages.${s}.ardupilot-sitl}/bin/ardusub";
          };
        });
      packages = levers.eachSystem (system:
        let pkgs = import nixpkgs { inherit system; };
            use-build-bom = galois-flakes.outputs.packages."${system}".build-bom-wrapper
              {
                extra-build-bom-flags = [
                  # "-E"
                  # "-v"

                  # AP_Common.c tries to ensure the right size for float
                  # constants via "static_assert(sizeof(1e6) == sizeof(float),
                  # ...)" which is obtained in gcc via
                  # -fsingle-precision-constant, but clang's version is
                  # -cl-single-precision-constant
                  "--inject-argument=-cl-single-precision-constant"
                ];
                # extra-buildInputs = [ pkgs.pkgsCross.gnu32.cmake ];

                # Use the default build-bom, but this can be overridden by adding
                # a different build-bom input and specifying it here:
                # build-bom = build-bom.packages.${system}.build-bom;

                # Use older clang/llvm because newer has import problems
                clang = if isSuperVolo then pkgs.clang_9 else pkgs.clang_12;
                llvm = if isSuperVolo then pkgs.llvm_9 else pkgs.llvm_12;
              };
            isSuperVolo = builtins.hasAttr "uavcan" CANBUS.packages.${system};
            # SuperVolo uses uavcan instead of pydronecan. Also, SuperVolo is
            # older and needs python2 packages.
            python = if isSuperVolo then pkgs.python2 else pkgs.python3;
            pythonpkgs = if isSuperVolo then pkgs.python2Packages else pkgs.python3Packages;
        in {
          default = self.packages.${system}.sitl_bc;

          empy = pythonpkgs.buildPythonPackage rec {
              name = "empy";
              src = empy-src;
              doCheck = false;
              pythonImportsCheck = [ "em" ];
              format = "setuptools";
          };
          mavproxy = pythonpkgs.buildPythonPackage rec {
              name = "mavproxy";
              src = mavproxy-src;
              propagatedBuildInputs = [
                self.packages.${system}.pymavlink
                pythonpkgs.pyserial
                pythonpkgs.numpy
              ];
              doCheck = false;
              pythonImportsCheck = [ "MAVProxy" ];
              format = "setuptools";
          };

          pymavlink = pythonpkgs.buildPythonPackage rec {
              name = "pymavlink";
              src = pymavlink-src;
              propagatedBuildInputs = [
                pythonpkgs.future
                pythonpkgs.lxml
              ];
              doCheck = false;
              pythonImportsCheck = [ "pymavlink" ];
              format = "setuptools";
              MDEF = "${mavlink-src}/message_definitions";
          };
          dronecan = CANBUS.packages.${system}.pydronecan or
            CANBUS.packages.${system}.uavcan;
          sim_vehicle = pkgs.stdenv.mkDerivation {
            name = "sim_vehicle";
            version = "1.0";
            src = "${ardupilot-src}/Tools/autotest";
            configurePhase = "";
            buildPhase = ''
              cat > sim_vehicle << EOF
              #!/usr/bin/env bash
              set -x
              export PATH=$PATH
              export PYTHONPATH=${self.packages.${system}.mavproxy}/lib:$out/lib:$PYTHONPATH
              echo Defaulting to arducopter via --vehicle-binary=${self.packages.${system}.sitl}/bin/arducopter
              echo Override via explicit --vehicle-binary specification
              python3 $out/bin/Tools/autotest/sim_vehicle.py --no-rebuild --no-configure --vehicle-binary=${self.packages.${system}.sitl}/bin/arducopter "\''${@}"
              EOF
              sed -i -e '/TMUX/s,screen",screen" -o "$TERM" = "screen-256color",' run_in_terminal_window.sh
            '';
            buildInputs = [
              pkgs.python3
              self.packages.${system}.sitl
              self.packages.${system}.mavproxy
            ];
            propagatedBuildInputs =
              let pp = pkgs.python3Packages;
              in [
                pp.pexpect
                pkgs.procps
                pkgs.tmux
                pkgs.xterm
              ];
            installPhase = ''
              mkdir -p $out/bin/Tools/autotest
              cp sim_vehicle.py $out/bin/Tools/autotest/
              install run_in_terminal_window.sh $out/bin/Tools/autotest/
              mkdir -p $out/lib/pysim
              cp -r pysim/* $out/lib/pysim/

              # sim_vehicle.py has some baked-in assumptions
              mkdir -p $out/bin/{ArduCopter,ArduPlane,ArduSub,Blimp,Rover}

              mkdir $out/bin/Tools/autotest/default_params
              cp -r default_params/* $out/bin/Tools/autotest/default_params

              install sim_vehicle $out/bin/
            '';
            # Usage: sim_vehicle --console --map --osd -v ArduCopter
            # KWQ: not fully working yet
          };
          sitl =
            let tgts = [
                  "all"
                  # copter heli plane rover sub antennatracker AP_Periph
                ];
                waf_flags = [
                  "--board" "sitl"
                  "--no-submodule-update"
                  # "--prefix=$out"
                ];
            in pkgs.stdenv.mkDerivation {
              name = "ardupilot-sitl";
              version = "1.0";
              src = ardupilot-src;
              buildInputs = [
                pkgs.gcc
                (if isSuperVolo
                 then pkgs.wafHook.override {
                   waf = pkgs.waf.override { python = python; };
                 }
                 else pkgs.wafHook)
                (python.withPackages (pp: [
                  self.packages.${system}.pymavlink
                  self.packages.${system}.empy
                  pp.pexpect
                  pp.setuptools
                  self.packages.${system}.dronecan
                ]))
              ];
              nativeBuildInputs = [ python ]; # KWQ
              wafConfigureFlags = waf_flags;
              wafBuildTargets = tgts;
              wafBuildFlags = waf_flags;
              wafInstallTargets = tgts;
              # n.b. the later Ardupilot waf configuration does not seem to want
              # to install into --prefix, --destdir, or --out, so it's done
              # manually in the postInstall hook here.  The install is handed as
              # expected for the older SuperVolo build.
              wafInstallFlags = waf_flags;
              postInstall =
                if isSuperVolo then ""
                else ''
                  mkdir $out/bin
                  cp build/sitl/bin/* $out/bin/
                  '';
              # Pre-configure fixes: the ardupilot waf requires that a number of
              # the submodules be actually present.  Use flake inputs to supplant
              # the use of git submodules.
              preConfigure = ''
                [ -d modules/waf ] && rmdir modules/waf || true
                # ln -s ${pkgs.waf.src} modules/waf
                ln -s ${waf-src} modules/waf
                sed -i -e "s,cfg.load('git_submodule'),if cfg.env.SUBMODULE_UPDATE: cfg.load('git_submodule')," wscript
                [ -d modules/mavlink ] && rmdir modules/mavlink || true
                ln -s ${mavlink-src} modules/mavlink
                [ -d modules/gtest ] && rmdir modules/gtest || true
                ln -s ${googletest-src} modules/gtest

                [ -d modules/DroneCAN/DSDL ] && rmdir modules/DroneCAN/DSDL || true
                [ -d modules/DroneCAN ] && ln -s ${CANBUS.packages.${system}.dsdl} modules/DroneCAN/DSDL

                [ -d modules/DroneCAN/dronecan_dsdlc ] && rmdir modules/DroneCAN/dronecan_dsdlc || true
                [ -d modules/DroneCAN ] && ln -s ${dronecan_dsdlc-src} modules/DroneCAN/dronecan_dsdlc

                # [ -d modules/DroneCAN/pydronecan ] && rmdir modules/DroneCAN/pydronecan || true
                [ -d modules/DroneCAN/libcanard ] && rmdir modules/DroneCAN/libcanard || true
                [ -d modules/DroneCAN ] && ln -s ${libcanard-src} modules/DroneCAN/libcanard

                [ -d modules/lwip ] && rmdir modules/lwip || true
                ln -s ${lwip-src} modules/lwip

                # Ensure that the build process can see the pydronecan package
                export PYTHONPATH=${self.packages.${system}.dronecan}/lib/python*/site-packages:$PYTHONPATH
              '';
              patches =
                # Apply all patches in the specified input location.  This allows
                # override of the patches applied if the ardupilot-source is
                # overridden.
                let contents = builtins.readDir ardupilot-patches;
                    isFile = n: contents.${n} == "regular";
                    files = builtins.filter isFile (builtins.attrNames contents);
                    fullPath = f: "${ardupilot-patches}/${f}";
                    patchfiles = builtins.map fullPath files;
                in patchfiles;
          };
          sitl_bc = use-build-bom self.packages.${system}.sitl;
        });
    };

}
