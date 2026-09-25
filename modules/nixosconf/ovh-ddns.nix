{ cfg, pkgs, config, ... }:
let
  zone = cfg.server.domain;
  iface = "eno1";

  ovh-ddns = pkgs.writers.writePython3Bin "ovh-ddns" { } ''
    import hashlib
    import json
    import os
    import subprocess
    import time
    import urllib.request
    from urllib.parse import urlencode

    APP_KEY = os.environ["OVH_APP_KEY"]
    APP_SECRET = os.environ["OVH_APP_SECRET"]
    CONSUMER_KEY = os.environ["OVH_CONSUMER_KEY"]
    ENDPOINT = os.environ.get("OVH_ENDPOINT", "https://eu.api.ovh.com/1.0")
    ZONE = os.environ["OVH_ZONE"]
    SUBDOMAINS = os.environ.get("OVH_SUBDOMAINS", ",*").split(",")
    IFACE = os.environ.get("OVH_IFACE", "eno1")


    def current_ipv6():
        cmd = ["ip", "-6", "-o", "addr", "show", "dev", IFACE, "scope", "global"]
        out = subprocess.check_output(cmd, text=True)
        for line in out.splitlines():
            fields = line.split()
            if "temporary" in fields:
                continue
            addr = fields[3].split("/")[0]
            if addr.startswith(("fc", "fd")):
                continue
            return addr
        raise SystemExit(f"no stable global IPv6 address found on {IFACE}")


    def ovh_time_delta():
        with urllib.request.urlopen(f"{ENDPOINT}/auth/time") as r:
            return int(r.read()) - int(time.time())


    def ovh(method, path, delta, body=None):
        ts = str(int(time.time()) + delta)
        body_str = json.dumps(body) if body is not None else ""
        url = ENDPOINT + path
        to_sign = [APP_SECRET, CONSUMER_KEY, method, url, body_str, ts]
        signature = "$1$" + hashlib.sha1(
            "+".join(to_sign).encode()
        ).hexdigest()
        req = urllib.request.Request(
            url,
            data=body_str.encode() if body is not None else None,
            method=method,
            headers={
                "X-Ovh-Application": APP_KEY,
                "X-Ovh-Consumer": CONSUMER_KEY,
                "X-Ovh-Timestamp": ts,
                "X-Ovh-Signature": signature,
                "Content-Type": "application/json",
            },
        )
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else None


    def main():
        current = current_ipv6()
        delta = ovh_time_delta()
        changed = False
        record_path = f"/domain/zone/{ZONE}/record"
        for sub in SUBDOMAINS:
            qs = urlencode({"fieldType": "AAAA", "subDomain": sub})
            ids = ovh("GET", f"{record_path}?{qs}", delta)
            label = f"{sub or '@'}.{ZONE}"
            if ids:
                record = ovh("GET", f"{record_path}/{ids[0]}", delta)
                if record["target"] == current:
                    print(f"{label} AAAA already {current}")
                    continue
                rec_path = f"{record_path}/{ids[0]}"
                ovh("PUT", rec_path, delta, {"target": current})
                print(f"updated {label} AAAA -> {current}")
            else:
                ovh(
                    "POST",
                    record_path,
                    delta,
                    {
                        "fieldType": "AAAA",
                        "subDomain": sub,
                        "target": current,
                        "ttl": 3600,
                    },
                )
                print(f"created {label} AAAA -> {current}")
            changed = True
        if changed:
            ovh("POST", f"{record_path.rsplit('/', 1)[0]}/refresh", delta)


    if __name__ == "__main__":
        main()
  '';
in {
  sops.secrets = {
    "ovh_app_key" = { sopsFile = ../../sops/oserv.yaml; };
    "ovh_app_secret" = { sopsFile = ../../sops/oserv.yaml; };
    "ovh_consumer_key" = { sopsFile = ../../sops/oserv.yaml; };
  };

  sops.templates."ovh-ddns.env".content = ''
    OVH_APP_KEY=${config.sops.placeholder.ovh_app_key}
    OVH_APP_SECRET=${config.sops.placeholder.ovh_app_secret}
    OVH_CONSUMER_KEY=${config.sops.placeholder.ovh_consumer_key}
  '';

  systemd.services.ovh-ddns = {
    description = "Sync oserv's IPv6 to OVH DNS (${zone})";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.iproute2 ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.sops.templates."ovh-ddns.env".path;
      Environment = [
        "OVH_ZONE=${zone}"
        "OVH_IFACE=${iface}"
        "OVH_SUBDOMAINS=,*"
      ];
      ExecStart = "${ovh-ddns}/bin/ovh-ddns";
    };
  };

  systemd.timers.ovh-ddns = {
    description = "Periodically sync oserv's IPv6 to OVH DNS";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
    };
  };

  environment.systemPackages = [ ovh-ddns ];
}
