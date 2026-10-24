# LG Buddy runtime CLI and GTK frontend, built from this checkout.
{
  lib,
  stdenv,
  rustPlatform,
  pkg-config,
  glib,
  wrapGAppsHook4,
  gtk4,
  libadwaita,
  dbus,
  python3,
  writeText,
  writeShellScriptBin,
  src,
  buildCommit ? "unknown",
}:
let
  cargoToml = lib.importTOML ../crates/lg-buddy/Cargo.toml;

  # The build sandbox has no /etc/dbus-1/session.conf, so `dbus-daemon --session`
  # cannot start there. Integration tests spawn it that way; point them at a
  # standalone session-style config instead.
  testBusConfig = writeText "lg-buddy-test-session.conf" ''
    <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
     "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
    <busconfig>
      <type>session</type>
      <listen>unix:tmpdir=/tmp</listen>
      <policy context="default">
        <allow user="*"/>
        <allow own="*"/>
        <allow send_destination="*" eavesdrop="true"/>
        <allow eavesdrop="true"/>
        <allow receive_sender="*"/>
      </policy>
    </busconfig>
  '';
  sandboxDbusDaemon = writeShellScriptBin "dbus-daemon" ''
    args=()
    for arg in "$@"; do
      if [ "$arg" = --session ]; then
        args+=(--config-file=${testBusConfig})
      else
        args+=("$arg")
      fi
    done
    exec ${lib.getExe' dbus "dbus-daemon"} "''${args[@]}"
  '';
in
rustPlatform.buildRustPackage {
  pname = "lg-buddy";
  inherit (cargoToml.package) version;
  inherit src;

  cargoLock.lockFile = ../Cargo.lock;

  nativeBuildInputs = [
    pkg-config
    glib # glib-compile-resources for the GUI build script
    wrapGAppsHook4
  ];

  buildInputs = [
    gtk4
    libadwaita
  ];

  # Private-bus tests start their own dbus-daemon; launcher tests exec python3.
  nativeCheckInputs = [
    sandboxDbusDaemon
    python3
  ];

  # build.rs embeds this in the release identity; leaving
  # LG_BUDDY_RELEASE_VERSION unset keeps the build on the dev channel.
  env.LG_BUDDY_BUILD_COMMIT = buildCommit;

  # GUI tests need a display; run the runtime crate's suite only. Starting the
  # lifecycle service requires systemctl in a trusted system location (/usr/bin
  # or /run/current-system), which the sandbox lacks, so that test is skipped.
  # The cucumber harness rejects libtest flags and runs on its own.
  checkPhase =
    let
      integrationTests = lib.pipe (builtins.readDir ../crates/lg-buddy/tests) [
        (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".rs" name))
        lib.attrNames
        (map (lib.removeSuffix ".rs"))
        (lib.remove "cucumber")
        (lib.concatMapStringsSep " " (name: "--test ${name}"))
      ];
      cargoTest = "cargo test -j $NIX_BUILD_CORES --offline --profile release --target ${stdenv.hostPlatform.rust.rustcTargetSpec} -p lg-buddy";
    in
    ''
      runHook preCheck
      ${cargoTest} --lib --bins ${integrationTests} -- \
        --test-threads=$NIX_BUILD_CORES \
        --skip sleep_activation_authorizes_before_saving_and_reuses_the_active_service
      ${cargoTest} --test cucumber
      runHook postCheck
    '';

  postInstall = ''
    install -Dm644 io.github.staphylococcus.LGBuddy.desktop \
      $out/share/applications/io.github.staphylococcus.LGBuddy.desktop
    substituteInPlace $out/share/applications/io.github.staphylococcus.LGBuddy.desktop \
      --replace-fail "Exec=/usr/bin/lg-buddy" "Exec=$out/bin/lg-buddy"
    install -Dm644 data/icons/hicolor/scalable/apps/io.github.staphylococcus.LGBuddy.svg \
      $out/share/icons/hicolor/scalable/apps/io.github.staphylococcus.LGBuddy.svg
  '';

  meta = {
    description = "Use an LG webOS TV as a Linux PC display with less reaching for the remote";
    homepage = "https://github.com/Staphylococcus/LG_Buddy";
    license = lib.licenses.gpl3Only;
    mainProgram = "lg-buddy";
    platforms = lib.platforms.linux;
  };
}
