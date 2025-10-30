let
  nixpkgs-unstable = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
    sha256 = "sha256:0ixzzfdyrkm8mhfrgpdmq0bpfk5ypz63qnbxskj5xvfxvdca3ys3";
  };

  pkgs = import nixpkgs-unstable {};
in
pkgs.mkShell {
  name = "elementary-zero";

  nativeBuildInputs = [
    pkgs.meson
    pkgs.ninja
    pkgs.vala
    pkgs.pkg-config
    pkgs.gettext
    pkgs.appstream-glib
    pkgs.desktop-file-utils
    pkgs.glib.dev
    pkgs.dpkg
  ];

  buildInputs = [
    pkgs.gtk3
    pkgs.pantheon.granite
    pkgs.libhandy
    pkgs.pantheon.switchboard
    pkgs.pantheon.wingpanel
    pkgs.libgee
    pkgs.json-glib
    pkgs.gsettings-desktop-schemas
    pkgs.gobject-introspection
    pkgs.zeitgeist
  ];
}


