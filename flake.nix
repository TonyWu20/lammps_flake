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
        kokkosOptions = [
          "ARCH_NATIVE=on"
          "ARCH_${pkgs.lib.strings.toUpper kokkosCudaArch}=on"
          "BINARY_DIR=${pkgs.kokkos}"
          # "SOURCE_DIR=${pkgs.kokkos}"
          "ENABLE_CUDA=yes"
          "ENABLE_OPENMP=yes"
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
            kokkos
            cmake
            gitMinimal
            pkg-config
            cudaPackages.cudatoolkit
            cudaPackages.cuda_nvcc
            mpi
            autoAddDriverRunpath
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

          phases = [ "unpackPhase" "patchPhase" "configurePhase" "buildPhase" "installPhase" ];

          # Convert package list to cmake flags
          packageFlags = builtins.map (pkg: pkgs.lib.cmakeBool "PKG_${(pkgs.lib.strings.toUpper pkg)}" true) packages;

          # Convert gpu options to cmake flags
          gpuFlags = builtins.map (opt: "-D${opt}") gpuExtraOptions;

          # Convert kokkos options to cmake flags  
          kokkosFlags = builtins.map (opt: "-DKokkos_${opt}") kokkosOptions;

          # Combine all flags
          cmakeFlags = packageFlags ++ gpuFlags ++ kokkosFlags ++ [
            "-DBUILD_SHARED_LIBS=ON"
            # "-DCMAKE_CUDA_COMPILER=${pkgs.cudaPackages.cudatoolkit}/bin/nvcc"
            "-DCMAKE_CXX_COMPILER=${pkgs.kokkos}/bin/nvcc_wrapper"
            "-DEXTERNAL_KOKKOS=ON"
            (lib.cmakeOptionType "string" "CUDA_NVCC_FLAGS" "-Wno-deprecated-gpu-targets")
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
          NIX_LDFLAGS = "-L${pkgs.cudaPackages.cudatoolkit}/lib -L${pkgs.cudaPackages.cudatoolkit}/lib64";
          NIX_CFLAGS_COMPILE = "-I${pkgs.cudaPackages.cudatoolkit}/include";

          # configurePhase = ''
          #   #runHook preConfigure
          #   
          #   # Create build directory
          #   mkdir -p build
          #   cd build
          #   
          #   # Configure with CMake
          #   cmake ../cmake ${pkgs.lib.escapeShellArgs cmakeFlags}
          # '';

          buildPhase = ''
            #runHook preBuild
            cmake --build . --target install -j$NIX_BUILD_CORES
            #runHook postBuild
          '';
          patchPhase = ''
            patchShebangs --build ${sourceRoot}/lib/kokkos/bin/*
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
