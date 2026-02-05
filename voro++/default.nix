{ stdenv, gnumake, lib, gcc, llvmPackages }:
stdenv.mkDerivation rec{
  name = "voro++-0.4.6";
  src = fetchTarball {
    url = "https://download.lammps.org/thirdparty/voro++-0.4.6.tar.gz";
    sha256 = "1kqvkcgxnf6r1w9py2dxzx7d3968alc6kyx4p3sxc4kasy4dhl85";
  };
  nativeBuildInputs = [ gnumake llvmPackages.stdenv ];
  phases = [ "unpackPhase" "buildPhase" "installPhase" ];
  buildFlags = [ "CXX=clang++" "CFLAGS='-fPIC -Wall -ansi -pedantic -O3'" "PREFIX=$out" ];
  buildPhase = ''
    make ${lib.concatStringsSep " " buildFlags}
  '';
  installPhase = ''
    make install PREFIX=$out
  '';
}
