# Helium browser (not in nixpkgs or Flathub): wraps the official AppImage.
# shortcut: pinned version, bump version + hash by hand from github.com/imputnet/helium-linux/releases
{ appimageTools, fetchurl }:
let
  pname = "helium";
  version = "0.21.3.1";
  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64.AppImage";
    hash = "sha256-qFQFlsk6RGMWBWAvO8Tu2lv/g+saOosC5NBKTIRz4p0=";
  };
  contents = appimageTools.extract { inherit pname version src; };
in appimageTools.wrapType2 {
  inherit pname version src;
  # Menu entry and icon from inside the AppImage
  extraInstallCommands = ''
    install -Dm444 ${contents}/helium.desktop -t $out/share/applications
    cp -r ${contents}/usr/share/icons $out/share/
  '';
}
