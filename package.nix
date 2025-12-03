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
    "dielectric"
    "electrode"
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
    "kim"
    "extra-fix"
    "extra-pair"
    "meam"
    "reaxff"
    "gpu"
    "openmp"
    "voronoi"
    "echemdid"
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
, pkgs
, kim
}:
let
  voro = pkgs.callPackage ./voro++ { };
in

stdenv.mkDerivation rec {
  pname = "lammps";
  version = "stable_22Jul2025";

  srcs = [
    (fetchFromGitHub {
      owner = "lammps";
      repo = "lammps";
      rev = version;
      name = "lammps";
      sha256 = "h2eh7AAiesS8ORXLwyipwYZcKvB5cybFzqmhBMfzVBU=";
    })
    (fetchFromGitHub {
      owner = "TonyWu20";
      repo = "lammps-hacks-public";
      rev = "master";
      name = "echemdid";
      sha256 = "r9In1Z9anSLUyxrWCboLrne9Vvp2LGEzrBWCZ4EiwZg=";
    })
  ];


  sourceRoot = pname;

  nativeBuildInputs = [
    cmake
    gitMinimal
    pkg-config
    voro
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

  postPatch = ''
    mkdir src/ECHEMDID
    cp ../echemdid/EChemDID-22July2025/fix_echemdid* src/ECHEMDID/
    cp ../echemdid/EChemDID-22July2025/fix_qeq* src/QEQ/
    sed -i "300i ECHEMDID" cmake/CMakeLists.txt
    echo "Add ECHEMDID and patch qeq"
  '';
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
      (lib.cmakeOptionType "filepath" "CMAKE_CXX_COMPILER" "/build/lammps/lib/kokkos/bin/nvcc_wrapper")
      (lib.cmakeOptionType "string" "CMAKE_CXX_FLAGS" "-Wno-deprecated-gpu-targets")
    ]);

  # Combine all flags
  cmakeFlags = packageFlags ++ gpuFlags ++ kokkosFlags ++ [
    (lib.cmakeBool "BUILD_SHARED_LIBS" true)
    (lib.cmakeBool "BUILD_OMP" true)
    (lib.cmakeOptionType "filepath" "VORO_LIBRARY" "${voro}/lib/libvoro++.a")
    (lib.cmakeOptionType "path" "VORO_INCLUDE_DIR" "${voro}/include/voro++")
    (lib.cmakeBool "DOWNLOAD_KIM" false)
  ];

  env = {
    NIX_ENFORCE_NO_NATIVE = 0;
    KIM-API_DIR = "${kim}/share/cmake/kim-api/";
  } //
  (lib.optionalAttrs cudaSupport {
    CUDA_PATH = "${cudaPackages.cudatoolkit}";
    CUDA_HOME = "${cudaPackages.cudatoolkit}";
    LD_LIBRARY_PATH = "${cudaPackages.cudatoolkit}/lib:${cudaPackages.cudatoolkit}/lib64:$LD_LIBRARY_PATH";
    LIBRARY_PATH = "${cudaPackages.cudatoolkit}/lib:${cudaPackages.cudatoolkit}/lib64:$LIBRARY_PATH";
    PATH = "${cudaPackages.cudatoolkit}/bin:$PATH";
    PKG_CONFIG_PATH = "${kim}/lib/pkgconfig/";
    # CXX = "/build/source/lib/kokkos/bin/nvcc_wrapper";
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
    "--suffix LD_LIBRARY_PATH : '${lib.getLib kim}/lib'"
  ];
  wrapperArgs = builtins.concatStringsSep " " wrapperOptions;

  patchPhase = ''
    patchShebangs --build /build/lammps/lib/kokkos/bin/*
    patchShebangs --build ${kim}/bin/
    runHook postPatch
  '';

  buildPhase = ''
    cmake --build . --target install -j$NIX_BUILD_CORES
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
