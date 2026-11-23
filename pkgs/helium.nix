# Helium browser (not in nixpkgs or Flathub): wraps the official AppImage.
# Version and hash are bumped weekly by scripts/update-helium (run by update.yml)
{ appimageTools, fetchurl }:
let
  pname = "helium";
  version = "0.22.2.1";
  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64.AppImage";
    hash = "sha256-8JDIESU/1ovH64lLmCoL4iHRcB937UtT9hRkma+LrgQ=";
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
