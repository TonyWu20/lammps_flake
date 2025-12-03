{
  description = "LAMMPS with configurable CUDA support";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    kim-api.url = "github:TonyWu20/kim-api-nix";
  };
  outputs = { self, nixpkgs, kim-api, ... }:
    let
      pkgsFor = { system, enableCUDA, overlays ? [ ] }: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        config.cudaSupport = enableCUDA;
        inherit overlays;
      };
      kim = kim-api.packages.x86_64-linux.default;
    in
    {
      packages.x86_64-linux =
        let
          pkgs = pkgsFor {
            system = "x86_64-linux";
            enableCUDA = true;
            overlays = [
              (final: prev: {
                mpi = prev.mpi.overrideAttrs {
                  configureFlags = prev.mpi.configureFlags ++ [
                    "--with-ucx=${pkgs.lib.getDev pkgs.ucx}"
                    "--with-ucx-libdir=${pkgs.lib.getLib pkgs.ucx}/lib"
                    "--enable-mca-no-build=btl-uct"
                  ];
                };
              })
            ];
          };
        in
        {
          default = pkgs.callPackage ./package.nix {
            cudaSupport = true;
            gpuArch = "sm_61";
            kokkosGpuArch = "pascal61";
            inherit kim;
          };
          sm_90 = pkgs.callPackage ./package.nix {
            cudaSupport = true;
            gpuArch = "sm_90";
            kokkosGpuArch = "hopper90";
            inherit kim;
          };
          # test
          # voro = pkgs.callPackage ./voro++ { };
        };
      packages.aarch64-darwin =
        let
          pkgs = pkgsFor {
            system = "aarch64-darwin";
            enableCUDA = false;
          };
        in
        {
          default = pkgs.callPackage ./package.nix {
            cudaSupport = false;
            gpuApi = "opencl";
            gpuArch = null;
            kokkosGpuArch = null;
            useGcc = false;
          };
        };
      devShells.x86_64-linux =
        let
          pkgs = pkgsFor {
            system = "x86_64-linux";
            enableCUDA = true;
            overlays = [
              (final: prev: {
                mpi = prev.mpi.overrideAttrs {
                  configureFlags = prev.mpi.configureFlags ++ [
                    "--with-ucx=${pkgs.lib.getDev pkgs.ucx}"
                    "--with-ucx-libdir=${pkgs.lib.getLib pkgs.ucx}/lib"
                    "--enable-mca-no-build=btl-uct"
                  ];
                };
              })
            ];
          };
        in
        {
          default = pkgs.mkShell {
            packages = [
              self.packages.x86_64-linux.default
              kim
            ];
            shellHook = ''
              export KIM_API_DIR="${kim}/share/cmake/kim-api"
            '';
          };
        };
    };
}
