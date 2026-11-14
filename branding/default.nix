# The JF monogram (white) as an icon theme entry: forlenza-os.svg plus PNGs for things that only take PNG
{ runCommand, librsvg }:
runCommand "forlenza-os-logo" { nativeBuildInputs = [ librsvg ]; } ''
  d=$out/share/icons/hicolor
  install -Dm644 ${./logo.svg} $d/scalable/apps/forlenza-os.svg
  for s in 96 256; do
    mkdir -p $d/''${s}x$s/apps
    rsvg-convert -w $s -h $s ${./logo.svg} -o $d/''${s}x$s/apps/forlenza-os.png
  done
''
