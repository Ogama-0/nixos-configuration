{ lib, buildGoModule, fetchFromGitHub }:
buildGoModule {
  pname = "deezer-cli";
  version = "0-unstable-2025-08-25";

  src = fetchFromGitHub {
    owner = "felipemarinho97";
    repo = "deezer-cli";
    rev = "43b1cbcf81e10fee115a54aaf379143b85dabaf0";
    hash = "sha256-/5J2kRN/Eb7lr92cdRS/ZJV3EygRqAS5V0fWCzid0fA=";
  };

  vendorHash = "sha256-xdvpcRSDTIPAKikaa15yI9jFVPNjn01kgifUbgTe2XI=";

  ldflags = [ "-s" "-w" ];

  meta = {
    description = "Command-line interface for browsing and searching the Deezer music catalog";
    homepage = "https://github.com/felipemarinho97/deezer-cli";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "deezer-cli";
  };
}
