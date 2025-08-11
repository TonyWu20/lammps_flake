{
  description = "LAMMPS with configurable CUDA support";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs = { nixpkgs, ... }:
    let
      pkgsFor = { system, enableCUDA }: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        config.cudaSupport = enableCUDA;
      };
    in
    {
      packages.x86_64-linux =
        let
          pkgs = pkgsFor {
            system = "x86_64-linux";
            enableCUDA = true;
          };
        in
        {
          default = pkgs.callPackage ./package.nix {
            cudaSupport = true;
            gpuArch = "sm_61";
            kokkosGpuArch = "pascal61";
          };
          sm_90 = pkgs.callPackage ./package.nix {
            enableCUDA = true;
            gpuArch = "sm_90";
            kokkosGpuArch = "hopper90";
          };
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
          };
        };
    };
}
