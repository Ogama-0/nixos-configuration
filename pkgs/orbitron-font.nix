{ stdenvNoCC, lib, fetchurl }:

# Just the Orbitron font on its own, rather than pulling in the whole
# nixpkgs `google-fonts` package - that one conflicts with the separately
# installed `merriweather` package (both ship the same font file path in
# their output, which `buildEnv` refuses to merge). SIL OFL licensed.
stdenvNoCC.mkDerivation {
  pname = "orbitron-font";
  version = "unstable";

  src = fetchurl {
    url = "https://github.com/google/fonts/raw/main/ofl/orbitron/Orbitron%5Bwght%5D.ttf";
    name = "orbitron-variable.ttf";
    hash = "sha256-9C2y3RbmQiWONXgpFuzrHc2+oG+5WNd61x3FljWH6P0=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm444 "$src" "$out/share/fonts/truetype/Orbitron[wght].ttf"
    runHook postInstall
  '';

  meta = {
    description = "Orbitron - futuristic/tech display typeface";
    homepage = "https://github.com/theleagueof/orbitron";
    license = lib.licenses.ofl;
    platforms = lib.platforms.all;
  };
}
