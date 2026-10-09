{ stdenvNoCC, lib, fetchurl }:

# Just the Klee One font on its own, for the same reason Orbitron is packaged
# this way rather than via nixpkgs `google-fonts` - see orbitron-font.nix. A
# pencil-handwriting typeface, used by the light greeter so the type belongs to
# the same world as the watercolour it is set on. SIL OFL licensed.
stdenvNoCC.mkDerivation {
  pname = "klee-one-font";
  version = "unstable";

  srcs = [
    (fetchurl {
      url = "https://github.com/google/fonts/raw/main/ofl/kleeone/KleeOne-Regular.ttf";
      name = "KleeOne-Regular.ttf";
      hash = "sha256-v0Bj8DDMKuat8KEUJKGIjlwOtEOPH20C9SKUr4aOmzo=";
    })
    (fetchurl {
      url = "https://github.com/google/fonts/raw/main/ofl/kleeone/KleeOne-SemiBold.ttf";
      name = "KleeOne-SemiBold.ttf";
      hash = "sha256-sDHsQmwjyhFD7x99WL7np57+EZ7WVBUvEhySIgKzA/0=";
    })
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    for f in $srcs; do
      install -Dm444 "$f" "$out/share/fonts/truetype/$(basename "$f" | sed 's/^[a-z0-9]*-//')"
    done
    runHook postInstall
  '';

  meta = {
    description = "Klee One - pencil-handwriting typeface with Latin and Japanese";
    homepage = "https://github.com/fontworks-fonts/Klee";
    license = lib.licenses.ofl;
    platforms = lib.platforms.all;
  };
}
