{ lib
, stdenv
, cudaSupport ? true
, lmpPackages ? [
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
  ]
, gpuApi ? "CUDA"
, gpuArch
, kokkosGpuArch
, useGcc ? true
, fetchFromGitHub
, cmake
, gitMinimal
, pkg-config
, cudaPackages
, autoAddDriverRunpath
, makeWrapper
, mpi
, llvmPackages
, darwin
, fftw
, lapack
, blas
, python313
, zlib
, zstd
, addDriverRunpath
}:

stdenv.mkDerivation rec {
  pname = "lammps";
  version = "stable_22Jul2025";

  src = fetchFromGitHub {
    owner = "lammps";
    repo = "lammps";
    rev = version;
    sha256 = "h2eh7AAiesS8ORXLwyipwYZcKvB5cybFzqmhBMfzVBU=";
  };

  sourceRoot = "./source";

  nativeBuildInputs = [
    cmake
    gitMinimal
    pkg-config
  ] ++
  (lib.optionals cudaSupport [
    cudaPackages.cudatoolkit
    cudaPackages.cuda_nvcc
    autoAddDriverRunpath
    makeWrapper
  ]) ++
  (lib.optionals useGcc [
    mpi
  ])
  ++ (
    lib.optionals (useGcc == false) [
      mpi
      llvmPackages.openmp
      darwin.DarwinTools
    ]
  )
  ;

  buildInputs = [
    fftw
    lapack
    blas
    python313
    zlib
    zstd
  ] ++
  (lib.optionals cudaSupport [
    cudaPackages.cudatoolkit
    cudaPackages.cuda_cudart
    cudaPackages.libcufft
  ]
  );
  propagatedBuildInputs = [
    fftw
    lapack
    blas
  ] ++
  (lib.optionals cudaSupport [
    cudaPackages.cudatoolkit
    cudaPackages.cuda_cudart
    cudaPackages.libcufft
  ]
  ) ++
  (lib.optionals useGcc [
    mpi
  ]) ++
  (lib.optionals (useGcc == false) [
    llvmPackages.openmp
  ])
  ;

  cmakeDir = "../cmake";

  enableParallelBuilding = true;

  phases = [ "unpackPhase" "patchPhase" "configurePhase" "buildPhase" "fixupPhase" ];

  # Convert package list to cmake flags
  packageFlags = builtins.map (pkg: lib.cmakeBool "PKG_${(lib.strings.toUpper pkg)}" true) lmpPackages;

  # Convert gpu options to cmake flags
  gpuFlags = [
    (lib.cmakeOptionType "string" "GPU_API" gpuApi)
  ] ++ (lib.optionals cudaSupport [
    (lib.cmakeOptionType "string" "GPU_ARCH" gpuArch)
    (lib.cmakeBool "CUDA_MPS_SUPPORT" true)
  ]);

  # Convert kokkos options to cmake flags  
  kokkosFlags = [
    (lib.cmakeBool "Kokkos_ARCH_NATIVE" true)
    (lib.cmakeBool "Kokkos_ENABLE_OPENMP" true)
  ]
  ++
  (lib.optionals cudaSupport
    [
      (lib.cmakeBool "Kokkos_ARCH_${lib.strings.toUpper kokkosGpuArch}" true)
      (lib.cmakeBool "Kokkos_ENABLE_CUDA" true)
      (lib.cmakeOptionType "string" "FFT_KOKKOS" "CUFFT")
      (lib.cmakeOptionType "filepath" "CMAKE_CXX_COMPILER" "/build/source/lib/kokkos/bin/nvcc_wrapper")
      (lib.cmakeOptionType "string" "CMAKE_CXX_FLAGS" "-Wno-deprecated-gpu-targets")
    ]);

  # Combine all flags
  cmakeFlags = packageFlags ++ gpuFlags ++ kokkosFlags ++ [
    (lib.cmakeBool "BUILD_SHARED_LIBS" true)
    (lib.cmakeBool "BUILD_OMP" true)
  ];

  env = {
    NIX_ENFORCE_NO_NATIVE = 0;
  } //
  (lib.optionalAttrs cudaSupport {
    CUDA_PATH = "${cudaPackages.cudatoolkit}";
    CUDA_HOME = "${cudaPackages.cudatoolkit}";
    LD_LIBRARY_PATH = "${cudaPackages.cudatoolkit}/lib:${cudaPackages.cudatoolkit}/lib64:$LD_LIBRARY_PATH";
    LIBRARY_PATH = "${cudaPackages.cudatoolkit}/lib:${cudaPackages.cudatoolkit}/lib64:$LIBRARY_PATH";
    PATH = "${cudaPackages.cudatoolkit}/bin:$PATH";
  }
  );
  cudaLibs =
    (lib.optionals cudaSupport [
      cudaPackages.cuda_cudart
      cudaPackages.libcufft
    ]);
  wrapperOptions = [
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
      ${lib.optionalString cudaSupport
         # expose runtime libraries necessary to use the gpu
         ''
           wrapProgram "$out/bin/lmp" ${wrapperArgs}
         ''
      }
    '';
}
