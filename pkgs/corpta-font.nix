{ stdenvNoCC, lib }:

# Personal-use-only demo font (see assets/fonts/Corpta-DEMO-LICENSE.txt) used
# by the laser bar's clock module. Not a full/commercial license - swap for
# a properly-licensed font if this ever needs to leave personal use.
stdenvNoCC.mkDerivation {
  pname = "corpta-demo-font";
  version = "demo";

  src = ../assets/fonts;

  installPhase = ''
    runHook preInstall
    install -Dm444 "$src/Corpta-DEMO.otf" "$out/share/fonts/opentype/Corpta-DEMO.otf"
    runHook postInstall
  '';

  meta = {
    description = "Corpta DEMO - personal-use-only demo font";
    license = "personal-use-only (demo), see assets/fonts/Corpta-DEMO-LICENSE.txt";
    platforms = lib.platforms.all;
  };
}
