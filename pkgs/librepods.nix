{ stdenv, lib, cmake, pkg-config, qt6, makeWrapper, openssl, bluez
, libpulseaudio, fetchFromGitHub }:
let
  src = fetchFromGitHub {
    owner = "kavishdevar";
    repo = "librepods";
    rev = "fa30d3c09aa8be1737988b8b0259e1710bd3a125";
    hash = "sha256-wKXST93GXGhlFSB7vbxbDduiF37f5wIcUxsz7M2tGJk=";
  };
in stdenv.mkDerivation {
  pname = "librepods";
  version = "dev";

  src = "${src}/linux";

  nativeBuildInputs = [ cmake pkg-config qt6.wrapQtAppsHook makeWrapper ];

  buildInputs = [
    qt6.qtbase
    qt6.qtconnectivity
    qt6.qtmultimedia
    qt6.wrapQtAppsHook
    openssl
    bluez
    libpulseaudio
  ];
  meta = {
    description = "AirPods liberated from Apple's ecosystem";
    homepage = "https://github.com/kavishdevar/librepods";
    license = lib.licenses.gpl3Only;
    maintainers = [ "kavishdevar" ];
    platforms = lib.platforms.unix;
    mainProgram = "librepods";
  };
}

