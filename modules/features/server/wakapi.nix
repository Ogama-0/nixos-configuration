{ ... }:
let
  # Both halves in one file, but two switches: oserv runs the server AND
  # reports to it, while the laptop and the school machine only report. One
  # flag would have started a Wakapi server on the laptop.
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.server.wakapi = {
        server.enable = lib.mkEnableOption "the Wakapi coding-time server itself, on oserv";
        client.enable = lib.mkEnableOption "~/.wakatime.cfg, reporting to that server";
      };
    };
in
{
  flake.featureModules.nixos.wakapi =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.server.wakapi.server.enable (
        let
          host = "wakapi";
        in
        {
          sops.secrets."wakapi_password_salt" = {
            sopsFile = ../../../sops/oserv.yaml;
          };
          sops.templates."wakapi.env".content = ''
            WAKAPI_PASSWORD_SALT=${config.sops.placeholder.wakapi_password_salt}
          '';

          services.wakapi = {
            enable = true;
            environmentFiles = [ config.sops.templates."wakapi.env".path ];

            settings = {
              server = {
                listen_ipv4 = "127.0.0.1";
                listen_ipv6 = "-";
                port = 3033;
                public_url = "http://${host}.${config.ogama.server.domain}";
              };
              db = {
                dialect = "sqlite3";
                name = "${config.services.wakapi.stateDir}/wakapi.db";
              };
              # We're serving over plain HTTP within the tailnet (no TLS, same as
              # the rest of the *.tail.${config.ogama.server.domain} stack). Wakapi's real
              # code default for this is "false" despite what config.default.yml's
              # comment suggests, which sets the session cookie's Secure flag —
              # browsers then silently drop it over HTTP, so login never sticks.
              security.insecure_cookies = true;
            };
          };

          services.caddy.virtualHosts."https://${host}.${config.ogama.server.ipv6Host}" = {
            extraConfig = ''
              reverse_proxy http://127.0.0.1:3033
            '';
          };
        }
      );
    };

  flake.featureModules.home.wakapi =
    { config, lib, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.server.wakapi.client.enable (
        {

          sops.secrets.wakatime_api_key.sopsFile = ../../../sops/wakatime.yaml;

          home.activation.wakatimeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                run cat > "$HOME/.wakatime.cfg" <<EOF
            [settings]  
            api_url = https://wakapi.${config.ogama.server.domain}/api/v1
            api_key = $(cat ${config.sops.secrets.wakatime_api_key.path})
            EOF
          '';
        }
      );
    };
}
