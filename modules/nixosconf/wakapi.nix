{ cfg, config, ... }:

let host = "wakapi.tail.${cfg.server.domain}";
in {
  sops.secrets."wakapi_password_salt" = { sopsFile = ../../sops/oserv.yaml; };
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
        public_url = "http://${host}";
      };
      db = {
        dialect = "sqlite3";
        name = "${config.services.wakapi.stateDir}/wakapi.db";
      };
      # We're serving over plain HTTP within the tailnet (no TLS, same as
      # the rest of the *.tail.${cfg.server.domain} stack). Wakapi's real
      # code default for this is "false" despite what config.default.yml's
      # comment suggests, which sets the session cookie's Secure flag —
      # browsers then silently drop it over HTTP, so login never sticks.
      security.insecure_cookies = true;
    };
  };

  services.caddy.virtualHosts."http://${host}" = {
    extraConfig = ''
      reverse_proxy http://127.0.0.1:3033
    '';
  };
}
