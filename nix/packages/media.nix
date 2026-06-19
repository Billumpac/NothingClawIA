  # Media packages: video, audio, players, screen sharing
  { pkgs }:

  with pkgs; [
    gpu-screen-recorder
    wf-recorder
    wayvnc
    sunshine

    ffmpeg
    x264
    playerctl

    # Audio
    pipewire
    wireplumber

    # Miracast stack (used by the Mirai screen-sharing daemon)
    gnome-network-displays
    miraclecast
    wpa_supplicant
    gst_all_1
    python3Packages.dbus-python

    # Desktop portal for standard Wayland screencasting (browsers, OBS, video calls)
    xdg-desktop-portal-hyprland

    # mDNS / Avahi (used by Mirai for source/sink discovery)
    avahi
  ]
