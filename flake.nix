{
  description = "LAMMPS with configurable CUDA support";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        config.allowUnfree = true;
        config.cudaSupport = true;
        inherit system;
      };
      lib = pkgs.lib;

      # Default configuration
      defaultConfig = rec {
        cudaArch = "sm_61"; # Default CUDA architecture
        kokkosCudaArch = "pascal61";
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
        ];
        gpuExtraOptions = [
          "GPU_ARCH=${cudaArch}"
          "GPU_API=CUDA"
          "CUDA_MPS_SUPPORT=on"
        ];
        kokkosOptions = with pkgs.lib;[
          (cmakeBool "Kokkos_ENABLE_CUDA" true)
          (cmakeBool "Kokkos_ENABLE_OPENMP" true)
          (cmakeBool "Kokkos_ARCH_${pkgs.lib.strings.toUpper kokkosCudaArch}" true)
          (cmakeBool "Kokkos_ARCH_NATIVE" true)
        ];
      };

      # Main lammps derivation with configurable parameters
      lammpsWithConfig =
        { cudaArch ? defaultConfig.cudaArch
        , kokkosCudaArch ? defaultConfig.kokkosCudaArch
        , packages ? defaultConfig.packages
        , gpuExtraOptions ? defaultConfig.gpuExtraOptions
        , kokkosOptions ? defaultConfig.kokkosOptions
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
            cudaPackages.cudatoolkit
            cudaPackages.cuda_nvcc
            mpi
            autoAddDriverRunpath
            makeWrapper
          ];

          buildInputs = with pkgs; [
            cudaPackages.cudatoolkit
            cudaPackages.cuda_cudart
            cudaPackages.libcufft
            fftw
            lapack
            blas
            python313
            zlib
            zstd
          ];
          propagatedBuildInputs = with pkgs; [
            cudaPackages.cudatoolkit
            cudaPackages.cuda_cudart
            cudaPackages.libcufft
            fftw
            lapack
            blas
            mpi
          ];

          cmakeDir = "../cmake";

          enableParallelBuilding = true;

          phases = [ "unpackPhase" "patchPhase" "configurePhase" "buildPhase" "fixupPhase" ];

          # Convert package list to cmake flags
          packageFlags = builtins.map (pkg: pkgs.lib.cmakeBool "PKG_${(pkgs.lib.strings.toUpper pkg)}" true) packages;

          # Convert gpu options to cmake flags
          gpuFlags = builtins.map (opt: "-D${opt}") gpuExtraOptions;

          # Convert kokkos options to cmake flags  
          kokkosFlags = kokkosOptions
            ++ [
            # (lib.cmakeBool "EXTERNAL_KOKKOS" true)
            (lib.cmakeOptionType "string" "FFT_KOKKOS" "CUFFT")
          ];

          # Combine all flags
          cmakeFlags = packageFlags ++ gpuFlags ++ kokkosFlags ++ [
            (lib.cmakeBool "BUILD_SHARED_LIBS" true)
            (lib.cmakeOptionType "filepath" "CMAKE_CXX_COMPILER" "/build/source/lib/kokkos/bin/nvcc_wrapper")
            (lib.cmakeOptionType "string" "CMAKE_CXX_FLAGS" "-Wno-deprecated-gpu-targets")
          ];

          env = {
            CUDA_PATH = "${pkgs.cudaPackages.cudatoolkit}";
            CUDA_HOME = "${pkgs.cudaPackages.cudatoolkit}";
            PATH = "${pkgs.cudaPackages.cudatoolkit}/bin:$PATH";
            # CXX = "${src}/source/lib/kokkos/bin/nvcc_wrapper";
            LD_LIBRARY_PATH = "${pkgs.cudaPackages.cudatoolkit}/lib:${pkgs.cudaPackages.cudatoolkit}/lib64:$LD_LIBRARY_PATH";
            LIBRARY_PATH = "${pkgs.cudaPackages.cudatoolkit}/lib:${pkgs.cudaPackages.cudatoolkit}/lib64:$LIBRARY_PATH";
            NIX_ENFORCE_NO_NATIVE = 0;
          };
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
            # expose runtime libraries necessary to use the gpu
            ''
              wrapProgram "$out/bin/lmp" ${wrapperArgs}
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
      packages.${system} = {
        default = lammps;
        # You can also expose custom versions
        lammps-sm90 = lammpsWithConfig { cudaArch = "sm_90"; kokkosCudaArch = "hopper90"; };
        lammps-sm80 = lammpsWithConfig { cudaArch = "sm_80"; kokkosCudaArch = "ampere80"; };
        lammps-sm75 = lammpsWithConfig { cudaArch = "sm_75"; kokkosCudaArch = "turing75"; };
        lammps-sm70 = lammpsWithConfig { cudaArch = "sm_70"; kokkosCudaArch = "volta70"; };
      };

      # Overlay for reuse
      overlays.default = overlay;

      # Example usage in other flakes:
      # Let users customize via overlay
      apps.${system} = {
        # Example app that uses custom configuration
        lammps-custom = {
          type = "app";
          program = "${lammpsWithConfig { cudaArch = "sm_80"; }}/bin/lmp";
        };
        lammps = {
          type = "app";
          program = "${lammps}/bin/lmp";
        };
      };
    };
}
