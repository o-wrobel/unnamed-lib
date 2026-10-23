{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    zig-shell.url = "github:o-wrobel/zig-nix-shell";
  };

  outputs = { self, nixpkgs, zig-shell }: let
  system = "x86_64-linux";
  pkgs = import nixpkgs { inherit system; };
  zigEnv = zig-shell.lib.zigShell pkgs;
  in {
    devShells.${system}.default = let
    ld_path = with pkgs; lib.makeLibraryPath [
      glfw
      vulkan-loader
      libGL
      libx11
      libxcursor
      libxrandr
      libxi
      libxkbcommon
      wayland
    ];
    in pkgs.mkShell {
      packages = zigEnv.packages ++ (with pkgs; [
        wgsl-analyzer
        vulkan-loader
      ]);

      shellHook = zigEnv.shellHook + ''
        export LD_LIBRARY_PATH=${ld_path}
        export LIBRARY_PATH=${ld_path}
      '';
    };
  };
}
