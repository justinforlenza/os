# Boot splash: plymouth's bgrt theme (firmware/vendor logo + spinner) with the JF logo as its watermark.
# Needed because NixOS only adds boot.plymouth.logo to the initrd's copy of bgrt; after switch-root bgrt reads
# plymouth's own spinner folder, which has no watermark, so machines whose GPU driver loads late
# (e.g. amdgpu) showed the splash without the logo.
{ runCommand, plymouth, logo }:
runCommand "forlenza-os-plymouth" { } ''
  d=$out/share/plymouth/themes/forlenza-os
  mkdir -p $d
  cp ${plymouth}/share/plymouth/themes/spinner/*.png $d/
  cp ${logo}/share/icons/hicolor/96x96/apps/forlenza-os.png $d/watermark.png
  sed -e "s|^ImageDir=.*|ImageDir=$d|" -e "s|^Name=.*|Name=ForlenzaOS|" -e "/^Name\[/d" \
    ${plymouth}/share/plymouth/themes/bgrt/bgrt.plymouth > $d/forlenza-os.plymouth
''
