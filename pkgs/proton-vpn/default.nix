# Proton VPN from Proton's official .debs, not nixpkgs' source build: the Smart and Stealth protocols run on protun,
# which is closed source and only ships prebuilt (in the amd64 API core: nm-protun-service + platform.abi3.so).
# Versions/hashes: sources.json, bumped weekly by scripts/update-proton-vpn (run by update.yml).
{
  lib,
  python3Packages,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  stdenv,
  libmnl,
  libnftnl,
  networkmanager,
  gobject-introspection,
  wrapGAppsHook4,
  libnotify,
  libayatana-appindicator,
  writableTmpDirAsHomeHook,
}:
let
  sources = lib.importJSON ./sources.json;
  fetchDeb = s: fetchurl { inherit (s) url sha256; };
  site = python3Packages.python.sitePackages;

  core = python3Packages.buildPythonPackage {
    pname = "proton-vpn-api-core";
    inherit (sources.core) version;
    format = "other";
    src = fetchDeb sources.core;

    # Home + runtime dir: importing creates config/runtime dirs (pythonImportsCheck)
    nativeBuildInputs = [ dpkg autoPatchelfHook gobject-introspection writableTmpDirAsHomeHook ];
    env.XDG_RUNTIME_DIR = "/tmp";
    buildInputs = [ stdenv.cc.cc.lib libmnl libnftnl ];
    propagatedBuildInputs = [ networkmanager ]; # NM typelib, used through gi
    dependencies = with python3Packages; [
      cryptography dbus-fast distro fido2 jinja2 packaging proton-core pycairo pygobject3 pynacl sentry-sdk
    ];

    unpackPhase = "dpkg-deb -x $src .";
    installPhase = ''
      mkdir -p $out/${site} $out/lib
      cp -r usr/lib/python3/dist-packages/. $out/${site}/
      cp -r usr/libexec usr/share $out/
      cp -r usr/lib/NetworkManager lib/systemd $out/lib/
      rm -r $out/share/doc

      # Helpers live in the store, not /usr/libexec
      for f in $out/lib/NetworkManager/VPN/nm-protun.name $out/share/dbus-1/system-services/*.service \
               $out/lib/systemd/system/*.service $out/share/polkit-1/actions/*.policy; do
        substituteInPlace $f --replace-fail /usr/libexec $out/libexec
      done
      # Was `exec /usr/bin/python3 -I -m …`; as a Python script, wrapPythonProgramsIn adds this package's deps
      cat > $out/libexec/proton-vpn-disable-kill-switch <<EOF
      #!${python3Packages.python.interpreter} -I
      import runpy
      runpy.run_module("proton.vpn.killswitch.disable", run_name="__main__", alter_sys=True)
      EOF
    '';
    postFixup = ''wrapPythonProgramsIn $out/libexec "$out $pythonPath"'';

    pythonImportsCheck = [ "proton.vpn.core" "proton.vpn.backend.networkmanager.protocol.protun" ];

    # networking.networkmanager.plugins: registers protun with NetworkManager, plus its D-Bus/systemd/polkit files
    passthru.networkManagerPlugin = "VPN/nm-protun.name";
    meta = {
      description = "Proton VPN core, with the protun tunnel (Smart and Stealth protocols)";
      license = lib.licenses.unfree; # protun is closed source
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode fromSource ];
      platforms = [ "x86_64-linux" ];
    };
  };
in
python3Packages.buildPythonApplication {
  pname = "proton-vpn";
  inherit (sources.app) version;
  format = "other";
  src = fetchDeb sources.app;

  nativeBuildInputs = [ dpkg gobject-introspection wrapGAppsHook4 writableTmpDirAsHomeHook ];
  env.XDG_RUNTIME_DIR = "/tmp";
  buildInputs = [ libnotify libayatana-appindicator ]; # typelibs: notifications, tray icon
  dependencies = with python3Packages; [
    core dbus-python distro packaging proton-core proton-keyring-linux pycairo pygobject3 requests
  ];

  unpackPhase = "dpkg-deb -x $src .";
  installPhase = ''
    mkdir -p $out/${site} $out/bin
    cp -r usr/lib/python3/dist-packages/. $out/${site}/
    cp -r usr/share $out/ && rm -r $out/share/doc
    cat > $out/bin/protonvpn-app <<EOF
    #!${python3Packages.python.interpreter}
    from proton.vpn.app.gtk.__main__ import main
    raise SystemExit(main())
    EOF
    chmod +x $out/bin/protonvpn-app
    # The wrapper renames the process, so the window class changes with it (as nixpkgs does)
    substituteInPlace $out/share/applications/proton.vpn.app.gtk.desktop \
      --replace-fail StartupWMClass=protonvpn-app StartupWMClass=.protonvpn-app-wrapped
  '';

  dontWrapGApps = true;
  preFixup = ''makeWrapperArgs+=("''${gappsWrapperArgs[@]}")'';

  pythonImportsCheck = [ "proton.vpn.app.gtk" ];
  passthru = { inherit core; };
  meta = {
    description = "Official Proton VPN client (Proton's .deb build, with Smart and Stealth)";
    homepage = "https://protonvpn.com/";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "protonvpn-app";
  };
}
