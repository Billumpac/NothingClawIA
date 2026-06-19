# NixOS module for NothingLess
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.nothingless;
in {
  options.programs.nothingless = {
    enable = lib.mkEnableOption "NothingLess shell";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The NothingLess package to use";
    };

    fonts.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install NothingLess fonts (including Phosphor Icons)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Pre-create the per-agent profile directory under
    # ~/.local/share/nothingless/agents/ so AgentStore can write
    # there on first use (each agent is one JSON file in this dir).
    # NixOS rebuilds the user's HOME on a shell re-login, so creating
    # the dir at activation time keeps it stable.
    home.activation.createNothingLessAgentsDir = lib.mkIf cfg.enable ''
      mkdir -p $HOME/.local/share/nothingless/agents
    '';

    # Register fonts with fontconfig (NixOS handles this via fonts.packages)
    fonts.packages = lib.mkIf cfg.fonts.enable (with pkgs; [
      roboto
      roboto-mono
      league-gothic
      terminus_font
      terminus_font_ttf
      dejavu_fonts
      liberation_ttf
      nerd-fonts.symbols-only
      nerd-fonts.iosevka
      noto-fonts
      noto-fonts-color-emoji
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      (pkgs.callPackage ../packages/phosphor-icons.nix { })
    ]);

    # Enable recommended services for full functionality
    services.upower.enable = lib.mkDefault true;
    services.power-profiles-daemon.enable = lib.mkDefault true;
    programs.gpu-screen-recorder.enable = lib.mkDefault true;
    networking.networkmanager.enable = lib.mkDefault true;
  };
}
