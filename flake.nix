{
  description = "LAMMPS with configurable CUDA support";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      isAarch64Darwin = pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64;
      pkgs = import nixpkgs {
        config.allowUnfree = true;
        config.cudaSupport = !isAarch64Darwin;
        inherit system;
      };
      lib = pkgs.lib;

      # Default configuration
      defaultConfig = {
        packages = [
          "asphere"
          "body"
          "class2"
          "colloid"
          "compress"
          "coreshell"
          "dipole"
          "granular"
          "kspace"
          "manybody"
          "mc"
          "misc"
          "molecule"
          "opt"
          "peri"
          "qeq"
          "replica"
          "rigid"
          "shock"
          "srd"
          "kokkos"
          "extra-fix"
          "meam"
          "reaxff"
          "gpu"
          "openmp"
        ];
        x86_64-linux = rec {
          cudaArch = "sm_61"; # Default CUDA architecture
          kokkosCudaArch = "pascal61";
          gpuExtraOptions = [
            "GPU_ARCH=${cudaArch}"
            "GPU_API=CUDA"
            "CUDA_MPS_SUPPORT=on"
          ];
          kokkosOptions = with pkgs.lib;[
            (cmakeBool "Kokkos_ENABLE_OPENMP" true)
            (cmakeBool "Kokkos_ENABLE_CUDA" true)
            (cmakeBool "Kokkos_ARCH_${pkgs.lib.strings.toUpper kokkosCudaArch}" true)
            (cmakeBool "Kokkos_ARCH_NATIVE" true)
          ];
        };
        aarch64-darwin = {
          cudaArch = null; # Default CUDA architecture
          kokkosCudaArch = null;
          gpuExtraOptions = [
            "GPU_ARCH=opencl"
          ];
          kokkosOptions = with pkgs.lib;[
            (cmakeBool "Kokkos_ENABLE_OPENMP" true)
            (cmakeBool "Kokkos_ARCH_NATIVE" true)
          ];
        };
      };

      # Main lammps derivation with configurable parameters
      lammpsWithConfig =
        { system ? "x86_64-linux"
        , cudaArch ? defaultConfig.${system}.cudaArch
        , kokkosCudaArch ? defaultConfig.${system}.kokkosCudaArch
        , packages ? defaultConfig.packages
        , gpuExtraOptions ? defaultConfig.${system}.gpuExtraOptions
        , kokkosOptions ? defaultConfig.${system}.kokkosOptions
        , ...
        }:
        pkgs.stdenv.mkDerivation rec {
          pname = "lammps";
          version = "stable_22Jul2025";

          src = pkgs.fetchFromGitHub {
            owner = "lammps";
            repo = "lammps";
            rev = version;
            sha256 = "h2eh7AAiesS8ORXLwyipwYZcKvB5cybFzqmhBMfzVBU=";
          };

          sourceRoot = "./source";

          nativeBuildInputs = with pkgs; [
            cmake
            gitMinimal
            pkg-config
            mpi
          ] ++
          (lib.optional (system == "x86_64-linux") [
            cudaPackages.cudatoolkit
            cudaPackages.cuda_nvcc
            autoAddDriverRunpath
            makeWrapper
          ]);

          buildInputs = with pkgs; [
            fftw
            lapack
            blas
            python313
            zlib
            zstd
          ] ++
          (lib.optional (system == "x86_64-linux") [
            cudaPackages.cudatoolkit
            cudaPackages.cuda_cudart
            cudaPackages.libcufft
          ]
          );
          propagatedBuildInputs = with pkgs; [
            fftw
            lapack
            blas
            mpi
          ] ++
          (lib.optional (system == "x86_64-linux") [
            cudaPackages.cudatoolkit
            cudaPackages.cuda_cudart
            cudaPackages.libcufft
          ]
          );

          cmakeDir = "../cmake";

          enableParallelBuilding = true;

          phases = [ "unpackPhase" "patchPhase" "configurePhase" "buildPhase" "fixupPhase" ];

          # Convert package list to cmake flags
          packageFlags = builtins.map (pkg: pkgs.lib.cmakeBool "PKG_${(pkgs.lib.strings.toUpper pkg)}" true) packages;

          # Convert gpu options to cmake flags
          gpuFlags = builtins.map (opt: "-D${opt}") gpuExtraOptions;

          # Convert kokkos options to cmake flags  
          kokkosFlags = kokkosOptions
            ++
            (lib.optional (system == "x86_64-linux")
              [
                (lib.cmakeOptionType "string" "FFT_KOKKOS" "CUFFT")
                (lib.cmakeOptionType "filepath" "CMAKE_CXX_COMPILER" "/build/source/lib/kokkos/bin/nvcc_wrapper")
                (lib.cmakeOptionType "string" "CMAKE_CXX_FLAGS" "-Wno-deprecated-gpu-targets")
              ]);

          # Combine all flags
          cmakeFlags = packageFlags ++ gpuFlags ++ kokkosFlags ++ [
            (lib.cmakeBool "BUILD_SHARED_LIBS" true)
          ];

          env = {
            NIX_ENFORCE_NO_NATIVE = 0;
          } ++
          (pkgs.lib.optional (system == "x86_64-linux") {
            CUDA_PATH = "${pkgs.cudaPackages.cudatoolkit}";
            CUDA_HOME = "${pkgs.cudaPackages.cudatoolkit}";
            LD_LIBRARY_PATH = "${pkgs.cudaPackages.cudatoolkit}/lib:${pkgs.cudaPackages.cudatoolkit}/lib64:$LD_LIBRARY_PATH";
            LIBRARY_PATH = "${pkgs.cudaPackages.cudatoolkit}/lib:${pkgs.cudaPackages.cudatoolkit}/lib64:$LIBRARY_PATH";
            PATH = "${pkgs.cudaPackages.cudatoolkit}/bin:$PATH";
          }
          );
          cudaLibs = with pkgs;[
            cudaPackages.cuda_cudart
            cudaPackages.libcufft
          ];
          wrapperOptions = with pkgs;[
            # ollama embeds llama-cpp binaries which actually run the ai models
            # these llama-cpp binaries are unaffected by the ollama binary's DT_RUNPATH
            # LD_LIBRARY_PATH is temporarily required to use the gpu
            # until these llama-cpp binaries can have their runpath patched
            "--suffix LD_LIBRARY_PATH : '${addDriverRunpath.driverLink}/lib'"
            "--suffix LD_LIBRARY_PATH : '${lib.makeLibraryPath (map lib.getLib cudaLibs)}'"
          ];
          wrapperArgs = builtins.concatStringsSep " " wrapperOptions;

          patchPhase = ''
            patchShebangs --build /build/source/lib/kokkos/bin/*
          '';

          buildPhase = ''
            #runHook preBuild
            cmake --build . --target install -j$NIX_BUILD_CORES
            #runHook postBuild
          '';

          postFixup =
            ''
              ${lib.optionalString (system == "x86_64-linux") 
                 # expose runtime libraries necessary to use the gpu
                 ''
                   wrapProgram "$out/bin/lmp" ${wrapperArgs}
                 ''
              }
            '';
        };

      # Create the default package with default configuration
      lammps = lammpsWithConfig { };

      # Create a more flexible overlay that allows configuration
      overlay = final: prev: {
        lammps = lammps;
        lammpsCustom = lammpsWithConfig;
      };
    in
    {
      packages.x86_64-linux = {
        system = "x86_64-linux";
        default = lammps;
        # You can also expose custom versions
        lammps-sm90 = lammpsWithConfig { cudaArch = "sm_90"; kokkosCudaArch = "hopper90"; };
        lammps-sm80 = lammpsWithConfig { cudaArch = "sm_80"; kokkosCudaArch = "ampere80"; };
        lammps-sm75 = lammpsWithConfig { cudaArch = "sm_75"; kokkosCudaArch = "turing75"; };
        lammps-sm70 = lammpsWithConfig { cudaArch = "sm_70"; kokkosCudaArch = "volta70"; };
      };
      packages.aarch64-darwin = {
        default = lammps {
          system = "aarch64-darwin";
        };
      };

      # Overlay for reuse
      overlays.default = overlay;

      # Example usage in other flakes:
      # Let users customize via overlay
      apps.${system} = {
        # Example app that uses custom configuration
        lammps = {
          type = "app";
          program = "${lammps}/bin/lmp";
        };
      };
    };
}
