# Adding a service to `oserv`

A checklist and the conventions behind it, for putting a new service on the
home server. Written after wiring up the Gatus/Prometheus status API
(2026-10-09); every gotcha below is one that actually bit during that work,
verified against the running machine rather than inferred from the modules.

## The shape of a service

A service is normally **one file** in `modules/nixosconf/<name>.nix`, added to
the `imports` list in `host/serveur/configuration.nix`. The file owns
everything about that service — the `services.<name>` block, its Caddy vhost,
its `systemd.tmpfiles.rules`, its sops secrets. Resist splitting the vhost out
into `caddy.nix`: NixOS merges `services.caddy.virtualHosts` across modules, so
keeping it next to the service is both possible and the existing convention
(`jellyfin.nix`, `wakapi.nix`, `qbittorrent.nix`, `status-page.nix` all do it).

Put it in `host/serveur/nixosconf/` instead only if it is genuinely
unshareable with the `personal` host — `backup-server.nix` and `grafana.nix`
are the examples.

The standard skeleton, following `wakapi.nix`:

```nix
{ cfg, config, ... }:

let host = "myservice.tail.${cfg.server.domain}";
in {
  services.myservice = {
    enable = true;
    # bind loopback: Caddy is the only thing that should reach it
    settings.server = { address = "127.0.0.1"; port = 1234; };
  };

  services.caddy.virtualHosts."http://${host}" = {
    extraConfig = ''
      reverse_proxy http://127.0.0.1:${
        toString config.services.myservice.settings.server.port
      }
    '';
  };
}
```

Never hardcode the domain, the username, or a storage path — they come from
`cfg` (`host/profiles.nix`), which is passed to every module via `specialArgs`.
Reference the port through `config.services.<name>.<portOption>` where the
module exposes one, so the vhost cannot drift from the service.

## Checklist

1. `modules/nixosconf/<name>.nix` with the service + its Caddy vhost.
2. Import it from `host/serveur/configuration.nix`.
3. **`git add` the new file** — Nix reads the flake through git, and an
   untracked file fails evaluation with "is not tracked by Git", not with a
   missing-import error.
4. **Add the DNS CNAME** (see below). This is the step with no trace in the
   repo and is the one that gets forgotten.
5. Add a Gatus endpoint in `modules/nixosconf/status-page.nix`.
6. Add a process-exporter matcher in `host/serveur/nixosconf/grafana.nix`.
7. sops secret, if it needs one.
8. `nix flake check`, then build the closure, then switch.

## DNS: `*.tail.ogama.me` is not a wildcard

Each name is an individual CNAME in the external `ogama.me` zone, managed at
the registrar, pointing at the tailnet host:

```
myservice.tail.ogama.me.  CNAME  neskwik.tail.ogama.me.  →  100.67.231.113
```

Nothing in this repo creates it, and Caddy will happily serve a vhost for a
name that does not resolve, so the failure mode is a service that works
perfectly from the server and is invisible from every other machine. Add the
record, then confirm with `dig +short myservice.tail.ogama.me` before
concluding anything is broken.

## Caddy conventions

- **`http://` scheme prefix = tailnet-only, plain HTTP.** The prefix disables
  Caddy's automatic HTTPS for that site. This is the default for everything on
  the tailnet, and is fine: the tailnet is already encrypted.
- **A `*.tail` name cannot have a certificate.** It resolves to a tailnet
  address, so no ACME challenge can validate it without DNS-01, which is not
  configured. A service that needs TLS needs a public name — see below.
- **A bare hostname = public, with ACME.** `jellyfin.ogama.me` and
  `rustical.ogama.me` do this. Do not add one unless the service is
  deliberately internet-facing. Three things about this path are not obvious:
  - **It is IPv6-only.** The name is a CNAME to
    `neskwik.portal.ogama.me`, which is an **AAAA** record holding this
    host's global IPv6 address. There is no A record anywhere in the chain,
    so `dig +short <name>` (an A-only query) prints the CNAME and nothing
    else — which looks exactly like a broken record. Use `dig AAAA` before
    concluding anything. IPv4-only clients cannot reach these names at all,
    which is why both services also keep a `*.tail` vhost.
  - **ACME HTTP-01 validates fine over IPv6**, so a bare vhost just works
    once the CNAME exists — no DNS-01, no credentials. Verify the result
    with `openssl s_client -6 -connect <name>:443 -servername <name>`;
    `Verify return code: 0` and a `Let's Encrypt` issuer mean it worked.
  - **Caddy will not generate the HTTP->HTTPS redirect**, because the
    `http://*.ogama.me` catch-all already claims port 80 for every
    subdomain. Write an explicit `http://` vhost with
    `redir https://{host}{uri} permanent`, or `http://` links land on the
    catch-all's 404 and look like a dead service.
- There is a catch-all `http://*.ogama.me` that answers 404, so a typo in a
  vhost name degrades to a clean 404 rather than silently landing on another
  backend.
- When proxying something whose API should not be fully exposed, use
  `handle` blocks to allow only the paths you mean and `respond 404` for the
  rest — `grafana.nix`'s `metrics.tail` vhost restricts Prometheus to
  `/api/v1/query*` this way. That restriction *is* the security control; a
  bare `reverse_proxy` would expose `/api/v1/status/config`, `/targets` and
  the admin TSDB endpoints to the whole tailnet.

## Picking a port

Check it is free before committing to it. Gatus defaults to 8080, which
`services.qbittorrent.webuiPort` already holds on this host; the collision
only shows up at runtime as a service that will not start. `ss -ltnp` on the
server is the authority. Ports currently in use include 2019 (Caddy admin),
2283/2281 (Immich), 3000 (Grafana), 3003 (Immich ML), 3030 (Loki), 3033
(Wakapi), 4000 (RustiCal), 8020 (calendar_syncer), 8080 (qBittorrent), 8081
(Calino's CORS proxy), 8085 (Gatus), 8096 (Jellyfin), 9001 (Prometheus),
9002 (node-exporter), 9256 (process-exporter).

## Firewall

Almost always nothing to do. Services bind `127.0.0.1`, Caddy's 80/443 are
already open in `caddy.nix`, and Tailscale handles reachability. Leave
`openFirewall = false` (several modules have it commented out for exactly this
reason) unless the service must be reachable off the tailnet.

## Monitoring: the Gatus endpoint

Add to `endpoints` in `modules/nixosconf/status-page.nix`:

```nix
{
  name = "MyService";
  group = "web";
  url = "http://myservice.tail.${cfg.server.domain}/health";
  interval = "15s";
  conditions = [ "[STATUS] == 200" "[RESPONSE_TIME] < 300" ];
}
```

Three rules, all load-bearing for the desktop widget that reads this API:

- **Exactly two conditions, status first, response time second.** The widget
  reads `conditionResults` positionally to get three states out of two
  booleans: status failed → down, status ok and time failed → degraded, both
  ok → up. One combined condition destroys the middle tier. For a `tcp://`
  probe, `[CONNECTED] == true` takes the first slot.
- **`key` is `{group}_{name}`**, lowercased with `/ _ . , space # + &` mapped
  to `-` (gatus `config/key/key.go`). It is the join key between the row, its
  Prometheus metrics and its widget label. Renaming a group or an endpoint is
  an API break, not a cosmetic change.
- **Verify the probe URL returns literally 200.** Jellyfin's `/` answers 302
  (redirect to `/web/`), which fails `[STATUS] == 200` on a perfectly healthy
  service — hence `/health`. Check with
  `curl -s -o /dev/null -w '%{http_code}' <url>` before committing, and prefer
  a real health path (`/health`, `/api/health`, `/ping`) over `/`.
- **A service behind HTTP basic auth answers 401, and that is its healthy
  state.** `calendar_syncer` authenticates every route including `/`, so its
  endpoint asserts `[STATUS] == 401`; demanding 200 there would show a
  correctly secured service as permanently down. A dead or wedged service
  still fails the condition, which is what the row is for.

Probe through the public hostname wherever a vhost exists: the question is
"can I use this", and that path includes DNS, Tailscale, Caddy and the
backend. Probe loopback only for things with no vhost.

## Monitoring: the process-exporter matcher

Add to `exporters.process.settings.process_names` in
`host/serveur/nixosconf/grafana.nix`, otherwise the service's row in Grafana
and in the status widget has no CPU/RAM:

```nix
{ name = "myservice"; comm = [ "myservice" ]; }
```

- **`comm` is the kernel's 15-character truncation of the process name, and
  Nix wrappers often prefix a dot.** qBittorrent's real `comm` is
  `.qbittorrent-no`, so a `comm = [ "qbittorrent-nox" ]` matcher silently
  matched nothing for as long as it existed — the group was simply absent
  from Prometheus, with no error anywhere. Always read the real value off the
  running system with `ps -eo comm=,args= | grep <name>` and use
  `cmdline = [ "<regex>" ]` when `comm` is truncated, wrapped, or too generic
  (Immich ML's `comm` is just `python3.13`).
- **`comm` matching is exact**, which is usually what you want: `grafana`
  matches the server but not its `gpx_grafana_ela` plugin helper.
- Confirm afterwards that the group actually exists:
  ```
  curl -s -G http://127.0.0.1:9001/api/v1/query \
    --data-urlencode 'query=namedprocess_namegroup_num_procs' \
    | jq -r '.data.result[].metric.groupname' | sort
  ```
- The `name` here does **not** have to match the Gatus endpoint name, and for
  half the services it does not (`media_immich` ↔ `immich-server`). Document
  the mismatch in a comment rather than renaming a matcher, which would break
  the existing Grafana dashboard.

## Secrets

sops, per `wakapi.nix`. Declare the secret, then either point the service at
the decrypted path or build an env file from a template:

```nix
sops.secrets."myservice_token" = { sopsFile = ../../sops/oserv.yaml; };
sops.templates."myservice.env".content = ''
  MYSERVICE_TOKEN=${config.sops.placeholder.myservice_token}
'';
```

Where the service reads a file directly, `owner = "<serviceuser>"` on the
secret is needed (`grafana.nix` does this). `sops/` is gitignored; never
inline a secret in a module.

## Verifying

```
nix flake check
nix build --no-link .#nixosConfigurations.oserv.config.system.build.toplevel
```

Both run without sudo and catch essentially every evaluation and build error,
so always run them before asking for a switch. Two more non-sudo checks worth
knowing:

```
# see the config a service module will actually generate
nix build --no-link --print-out-paths \
  .#nixosConfigurations.oserv.config.services.<name>.configFile | xargs cat

# see the rendered Caddyfile
nix build --no-link --print-out-paths \
  .#nixosConfigurations.oserv.config.services.caddy.configFile
```

Then `sudo nixos-rebuild switch --flake .#oserv`, and afterwards
`systemctl status <name>` plus a `curl` through the real hostname.

A vhost can be tested before its DNS record exists by sending the `Host`
header by hand, which exercises the identical Caddy site:

```
curl -s -H 'Host: myservice.tail.ogama.me' http://127.0.0.1/
```

## Two upstream API quirks worth not rediscovering

- Gatus's `/api/v1/endpoints/statuses` returns only the **newest 50 results
  per endpoint** (`api.DefaultPageSize = 50`), capped at
  `storage.maximumNumberOfResults`. A short history is pagination, not data
  loss — pass `?pageSize=100`.
- Prometheus's global `scrape_interval` here is **1m**, so any
  `rate(...[1m])` returns *nothing*: `rate()` needs two samples in the window.
  Either widen the window to `[5m]` or set a per-job `scrape_interval = "15s"`
  (the `process` job does this). Prefer the per-job override only for small
  jobs — process-exporter is ~16 series, where node-exporter is thousands.
