# Calino — a browser-side CalDAV client (https://calino.io). Upstream ships
# a Docker image only, so this builds the static site and the small CORS
# proxy that ships next to it out of the source tree.
#
# `siteUrl` is baked in at build time (Vite inlines VITE_SITE_URL into
# index.html's canonical/OpenGraph tags), so the package is per-deployment
# rather than generic — it is instantiated from flake.nix with the server's
# own hostname.
{ lib, stdenv, fetchFromGitHub, fetchPnpmDeps, pnpmConfigHook, pnpm_10_latest
, nodejs_22, siteUrl }:

stdenv.mkDerivation (finalAttrs: {
  pname = "calino";
  version = "0.39.1";

  src = fetchFromGitHub {
    owner = "Ivan-Malinovski";
    repo = "calino";
    tag = "v${finalAttrs.version}";
    hash = "sha256-WSSLIRnoBXEBYVivy5Tjt446hhgExoxTg6vQYONe+u0=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    # pnpm_10 is pinned at 10.34.0 upstream, which 26.05 marks insecure;
    # _latest is the 10.34.5 patch release.
    pnpm = pnpm_10_latest;
    fetcherVersion = 3;
    hash = "sha256-VB/DQoqIv5OWmoSqBr0LEHxtxrG9C/4MUPUu8N+9up4=";
  };

  nativeBuildInputs = [ nodejs_22 pnpm_10_latest pnpmConfigHook ];

  env = {
    VITE_SITE_URL = siteUrl;
    # Permits the browser to talk to a plain-HTTP DAV server, which is
    # exactly our case: rustical is served over http:// on the tailnet.
    # Without this the app refuses to connect at all.
    CALINO_SELF_HOSTED = "true";
    # The service worker needs a Service-Worker-Allowed header that the
    # Caddy vhost does not set; leaving it off avoids a half-working
    # offline mode.
    CALINO_ENABLE_SW = "false";
  };

  buildPhase = ''
    runHook preBuild
    pnpm build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/calino
    cp -r dist $out/share/calino/web
    install -Dm644 proxy/server.mjs $out/share/calino/proxy/server.mjs
    runHook postInstall
  '';

  meta = {
    description = "A beautiful CalDAV client for the web";
    homepage = "https://calino.io";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
})
