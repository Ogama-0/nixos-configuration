# The calendar stack on `oserv`

Three services, added 2026-10-15, modelled on
[pixilie's VPS setup](https://github.com/pixilie/nix-configuration):

| Service | Module | Port | Host | What it is |
|---|---|---|---|---|
| RustiCal 0.16 | `modules/nixosconf/rustical.nix` | 4000 | `rustical.ogama.me` (HTTPS) + `rustical.tail.ogama.me` | The CalDAV/CardDAV server. Everything else points at it. |
| calendar_syncer | `modules/nixosconf/calendar-syncer.nix` | 8020 | `calsync.tail.ogama.me` | Mirrors ICS subscriptions into RustiCal, and keeps two CalDAV calendars in sync. |
| Calino | `modules/nixosconf/calino.nix` | 8081 (proxy) | `calino.tail.ogama.me` | A CalDAV client that runs in the browser, talking to RustiCal directly. |

They follow every convention in `adding-a-server-service.md`: loopback
binds, a Gatus endpoint each (group `calendar`), a process-exporter
matcher each, and a row each in the Quickshell widget's `serviceList`.
RustiCal additionally carries a public, certificate-bearing vhost, for the
reason below.

## Where RustiCal comes from

Stable nixpkgs carries 0.12.15; this runs the 0.16 line from
`nixpkgs-unstable`, so `rustical.nix` takes **both** the package and the
NixOS module from that input, with `disabledModules` removing the stable
one. They have to move together: 0.13 renamed `http.host`/`http.port` to a
single `http.bind` and put the server behind a `serve` subcommand, so the
stable module's ExecStart does not start a 0.16 binary and its generated
`config.toml` uses keys that binary rejects. The version therefore tracks
the `nixpkgs-unstable` input rather than anything pinned here — `nix flake
update nixpkgs-unstable` is what moves it.

Upgrading across that gap runs sqlite migrations (four of them land after
0.12: `drop_calendar_timezone`, `add_calendar_uid`, `birthday_calendars`,
`dav_push_vapid`) and they are one-way in practice. **Copy
`/var/lib/private/rustical/db.sqlite3` somewhere before the first 0.16
switch**, and note that rolling the generation back afterwards gives you an
old binary pointed at a migrated database.

`calendar_syncer` is a **private** repo, pulled as a flake input over SSH.
`nix flake lock` and the non-sudo `nix build` need a key that can read it;
`sudo nixos-rebuild` does not, because by then the input is already in the
store and is verified by narHash. Build before switching (which is what
`adding-a-server-service.md` says to do anyway) and this never comes up.

## RustiCal has two names, and needs both

RustiCal builds its session cookie with `.with_secure(true)` hardcoded in
`src/app.rs` (still so in 0.16.0), with no config option. Over plain HTTP
the browser drops that cookie and **the frontend login silently never
sticks** — no server-side error, the form just comes back. Token creation
can dodge this through the CLI (step 4), but listing and revoking tokens,
and browsing calendars, all live in the frontend. So:

| Name | Scheme | For |
|---|---|---|
| `rustical.ogama.me` | HTTPS, real cert | The web frontend, and any client off the tailnet |
| `rustical.tail.ogama.me` | plain HTTP | CalDAV from IPv4-only or tailnet-only clients |

The public name rides the same portal `jellyfin.ogama.me` uses: a CNAME to
`neskwik.portal.ogama.me`, which is an **AAAA** record holding this host's
global IPv6 address. ACME's HTTP-01 challenge validates over IPv6 without
any extra configuration — no DNS-01, no API credentials, nothing beyond
dropping the `http://` prefix on the vhost.

Two traps in that chain:

- **`dig +short rustical.ogama.me` looks broken.** It is an A-only query,
  and there is no A record in the chain — it prints the CNAME and stops.
  Use `dig AAAA`. This cost an hour once already.
- **Caddy does not generate the HTTP→HTTPS redirect**, because the
  `http://*.ogama.me` catch-all already owns port 80 for every subdomain.
  `rustical.nix` writes it by hand.

The flip side of the public name is real exposure: CalDAV accepts app
tokens only, but the frontend accepts the principal's password and RustiCal
does no rate limiting. Use a long random password for the principal, and
one app token per client so any of them can be revoked alone.

**Google sync is still not wired up.** It is OAuth2-only and Google refuses
a non-`https://` redirect URI, and `calsync` is still tailnet-plain-HTTP —
so `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` stay absent from the env
template. Giving calsync a public vhost the same way is now all it would
take; ICS mirroring and CalDAV↔CalDAV sync need neither.

## One-time setup

### 1. The sops secret

`calendar_syncer` runs with **no authentication at all** if
`CALSYNC_WEB_PASSWORD` is unset, and its UI holds the CalDAV credentials of
every account it syncs. The build fails until the key exists, which is the
intended behaviour:

```
sops sops/oserv.yaml      # add: calsync_web_password: <a long random string>
```

### 2. DNS

Four new CNAMEs in the external `ogama.me` zone. Nothing in this repo
creates them. Three point at the tailnet host like every other `*.tail`
name; the fourth is the public one, pointing at the IPv6 portal exactly as
`jellyfin.ogama.me` does:

```
rustical.tail.ogama.me.  CNAME  neskwik.tail.ogama.me.
calsync.tail.ogama.me.   CNAME  neskwik.tail.ogama.me.
calino.tail.ogama.me.    CNAME  neskwik.tail.ogama.me.
rustical.ogama.me.       CNAME  neskwik.portal.ogama.me.
```

**The public record has to exist before the switch**, or Caddy's ACME
challenge fails and `https://rustical.ogama.me` serves a TLS error instead
of a login page.

Confirm the tail names with `dig +short <name>`, but check the public one
with **`dig AAAA`** — the portal chain has no A record at all, so an
A-only query prints the CNAME and nothing else and looks broken when it is
fine.

### 3. A RustiCal principal

Users live in RustiCal's sqlite database, not in the Nix config. The CLI
reads the same `/etc/rustical/config.toml` the service does, so it finds
the right database on its own — the catch is *which user* it runs as. The
unit uses `DynamicUser`, so there is no persistent `rustical` account to
`sudo -u` into, and the state actually lives in `/var/lib/private/rustical`
with `/var/lib/rustical` as a symlink to it. Borrow the service's own
identity with a transient unit instead:

```
sudo systemctl stop rustical
sudo systemd-run --pty -p DynamicUser=yes -p StateDirectory=rustical \
  rustical principals create ogama --password -n "Oscar"
sudo systemctl start rustical
```

`--pty` is needed for the password prompt, and the stop/start is because
sqlite takes a single writer. `rustical principals list` the same way to
check the result.

### 4. An app token

**CalDAV Basic auth accepts app tokens only** — never the principal's
password. `validate_app_token` is the single credential path in
`crates/store/src/auth/middleware.rs`, so every client needs its own token.
Make one per client (`calendar_syncer`, Calino, phone, Thunderbird) so any
one of them can be revoked alone.

Two ways, both fine:

```
# CLI — 0.16 added this; no browser involved. Prints the token once.
sudo systemctl stop rustical
sudo systemd-run --pty -p DynamicUser=yes -p StateDirectory=rustical \
  rustical principals app-token create --name calendar_syncer ogama
sudo systemctl start rustical
```

or open <https://rustical.ogama.me>, log in as the principal from step 3,
and create them there — which is also where you go to *list* and *revoke*
them.

The browser route is what the TLS vhost exists for: over `http://` the
login fails silently. If the certificate is ever broken, either use the CLI
above or tunnel in — `ssh -L 4000:127.0.0.1:4000 ogama_serv@neskwik.tail.ogama.me`
and `http://localhost:4000`, localhost being a secure context.

### 5. Point calendar_syncer at RustiCal

At `http://calsync.tail.ogama.me` (user = `ogama_serv`, password = the sops
secret):

1. **Comptes → Ajouter un compte CalDAV**: URL
   `https://rustical.ogama.me/caldav/`, your principal id, and the app
   token from step 4.
2. Add the calendars you want on the account page.
3. **Calendriers → Ajouter un abonnement** for each ICS/webcal feed.
4. **Nouvelle synchronisation**, mirror mode, one per feed.

### 6. Calino

Open `http://calino.tail.ogama.me` and add the server
`https://rustical.ogama.me/caldav/` with the same principal and a
*separate* app token. Two things make this work and are easy to undo by
accident:

- The package is built with `CALINO_SELF_HOSTED=true`, which permits
  connections to a plain-HTTP DAV server. That was load-bearing before
  RustiCal had a certificate and is now only a fallback — but leave it on,
  or a renewal failure turns into "Calino refuses to connect" with no
  obvious link to the cause.
- RustiCal's vhost sends CORS headers for exactly the
  `http://calino.tail.ogama.me` origin, including the WebDAV verbs in the
  preflight. A browser treats only GET/HEAD/POST as simple requests, so
  without that preflight block every `PROPFIND` — i.e. every read — is
  blocked.

ICS feeds added *inside* Calino go through its CORS proxy instead, and the
proxy's `ALLOWED_TARGETS` is an allowlist (currently `zeus.ionis-it.com`,
the EPITA calendar). A feed on any other host returns 403 until its host is
added in `calino.nix`; that allowlist is the proxy's only real protection
against being used as an open relay, so extend it, don't empty it.

## Overlap with the laptop's own calendar sync

`modules/home-manager/calendar-sync.nix` already pulls ICS feeds straight
onto the `personal` laptop with `vdirsyncer` for `khal` and the
`Calendar.qml` widget. Both are kept: this stack is server-side and feeds
every device through RustiCal, that one is a local read-only copy that
works with the server down. Nothing prevents both from mirroring the *same*
feed, and if both do, `khal` shows every event twice — so when a feed moves
into `calendar_syncer`, drop it from the `calendars` set in
`calendar-sync.nix`.

## Monitoring notes

- **Calsync's Gatus condition is `[STATUS] == 401`, not 200.** Basic auth
  fronts every route including `/`, and the probe sends no credentials, so
  401 is the healthy answer. It still fails on a dead or wedged service.
- **Calino is probed at `/proxy/health`, not `/`.** Caddy serves the site
  from the nix store and would answer 200 with the proxy unit dead; the
  proxy is the half that can break.
- **RustiCal is the only `https://` probe**, since it is the only vhost
  with a certificate. It answers 200 `Pong!` at `/ping` with no auth, so
  that row doubles as a certificate alarm: a renewal that stops working
  (revoked OVH credentials, say) turns it red while the service itself is
  perfectly healthy. Check `journalctl -u caddy | grep -i acme` before
  suspecting RustiCal.
- The process matcher for Calino covers the proxy only — the site is static
  files served by Caddy and has no process, so that row's CPU/RAM is the
  proxy's.
