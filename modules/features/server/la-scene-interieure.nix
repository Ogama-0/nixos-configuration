{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.server.laSceneInterieure.enable = lib.mkEnableOption "the la-scene-interieure site and its deploy job";
    };
in
{
  flake.featureModules.nixos.laSceneInterieure =
    { config, lib, pkgs, inputs, ... }:
    {
      # The extra entries instruct the module system and cannot live inside
      # mkIf, so they apply whether or not the feature is enabled. What they
      # pull in only declares options and gates its own behaviour.
      imports = [
        sharedOptions
        inputs.lsi-web-interface.nixosModules.paquet
      ];

      config = lib.mkIf config.ogama.server.laSceneInterieure.enable (
        let
          # The app speaks plain HTTP and Socket.IO on this one port (see
          # app/production.ts), so the vhost at the bottom is a bare `reverse_proxy` —
          # Caddy upgrades WebSockets by itself.
          web-port = 3500;

          pubVitrineHost = "lsi.${config.ogama.server.domain}";
          pubAppHost = "app.${pubVitrineHost}";
          vitrineHost = "lsi.ipv6.${config.ogama.server.domain}";
          appHost = "app.${vitrineHost}";

          configuration = "${config.ogama.identity.homePath}/nixos-configuration";

          # Read out of flake.lock rather than written here, because the two must agree
          # and nothing would have caught it if they did not: the updater compares this
          # branch's remote head against the *locked* rev, so pointing it at a branch
          # the input is not locked to means they never compare equal — every tick would
          # bump the lock, rebuild, still disagree, and deploy again ten minutes later,
          # forever. (The dirty-tree interlock below happens to mask it, which is worse,
          # not better: it would start the day the tree was clean.)
          #
          # `ref` is absent from the lock when the input tracks the remote's default
          # branch, hence the fallback. Change the `?ref=` in flake.nix and this follows.
          #
          # The URL comes from the same place, for the same reason: `git ls-remote` has
          # to interrogate the repository the input is actually locked to. It arrives in
          # `ssh://` form rather than the `git@host:path` shorthand; ls-remote and the
          # pinned known-hosts file treat the two identically.
          verrou = builtins.fromJSON (builtins.readFile ../../../flake.lock);
          entree = verrou.nodes.lsi-web-interface;
          branch = lib.removePrefix "refs/heads/" (entree.locked.ref or "main");
          origin = entree.locked.url;

          requireCleanTree = false;

          # Auto-deploy on push. Turning this off also drops the sops deploy key, which
          # is the *only* thing in this module that needs one — the app runs from the
          # store and touches no git. So set this to false to switch before the key
          # exists: everything else here works, and deploying becomes
          #   nix flake update lsi-web-interface && sudo nixos-rebuild switch --flake .#oserv
          autoFollow = true;

          # Pinned rather than StrictHostKeyChecking=accept-new, which trusts whatever
          # answers the first time. GitHub's published host keys
          # (https://api.github.com/meta, "ssh_keys"), fetched 2026-11-01. If GitHub
          # rotates them every fetch starts failing with a host-key mismatch; that is
          # the intended failure mode, so re-fetch rather than loosening the check.
          knownHosts = pkgs.writeText "lsi-github-known-hosts" ''
            github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
            github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
            github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
          '';

          ClePath = if autoFollow then config.sops.secrets."lsi_deploy_key".path else "/dev/null";

          gitSsh = lib.concatStringsSep " " [
            "${pkgs.openssh}/bin/ssh"
            "-i ${ClePath}"
            "-o IdentitiesOnly=yes"
            "-o IdentityAgent=none"
            "-o UserKnownHostsFile=${knownHosts}"
            "-o StrictHostKeyChecking=yes"
            "-o ConnectTimeout=15"
            "-o BatchMode=yes"
          ];
        in
        {

          services.laSceneInterieure = {
            enable = true;
            port = web-port;

            # Upstream defaults to 3000, which is Grafana on this host (see
            # docs/adding-a-server-service.md, "Picking a port").

            publicUrl = "https://${pubAppHost}";

            package =
              inputs.lsi-web-interface.packages.${pkgs.stdenv.hostPlatform.system}.la-scene-interieure.override
                {
                  origineApplication = "https://${pubAppHost}";
                  origineSite = "https://${pubVitrineHost}";
                };

            vitrine.enable = true;

            environment.ORIGINE_SITE = "https://${pubVitrineHost}";

            #   sops.templates."lsi.env".content = "BREVO_API_KEY=${...placeholder...}";
            #   systemd.services.la-scene-interieure.serviceConfig.EnvironmentFile =
            #     config.sops.templates."lsi.env".path;
          };

          sops.secrets = lib.optionalAttrs autoFollow {
            "lsi_deploy_key" = {
              sopsFile = ../../../sops/oserv.yaml;
              owner = config.ogama.identity.user;
              mode = "0400";
            };
          };

          # ---------------------------------------------------------------------------
          # Following the branch flake.lock pins — refs/heads/main today. The unit
          # descriptions below interpolate it, so `systemctl status` names it out loud.
          #
          # Pull, not push: this host has nothing open to the internet and sits behind
          # Tailscale, so an Actions job cannot reach it without joining the tailnet
          # and holding a write-capable key. Polling needs neither.
          #
          # Because the app is a derivation now, "deploy" means bumping flake.lock and
          # rebuilding — so a push costs a full rebuild and leaves a lock commit in
          # this repo's history. That is the trade for knowing exactly what runs.
          systemd.services.la-scene-interieure-maj = lib.mkIf autoFollow {
            description = "La Scène intérieure — suit ${branch} et reconstruit";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];

            # This unit runs `nixos-rebuild switch`, and that switch will restart every
            # unit whose definition changed — including this one, killing the deploy
            # halfway through. NixOS's own system.autoUpgrade sets this for exactly the
            # same reason. It bites precisely when this module is what changed, which is
            # the most likely moment for a deploy to be running.
            restartIfChanged = false;

            # `path` *replaces* PATH (NixOS adds only coreutils/findutils/grep/sed/
            # systemd on top), so anything the script calls has to be listed. util-linux
            # is here for runuser: it lives in /run/current-system/sw/bin, which is not
            # on a unit's PATH, so without this the script died with "runuser: command
            # not found" at the first privilege drop. It never showed up in testing
            # because every run so far exited early at the revs-equal check — the whole
            # second half of this script had never executed once.
            path = [
              pkgs.git
              pkgs.openssh
              pkgs.jq
              pkgs.util-linux
              pkgs.systemd
              config.nix.package
            ];

            environment = {
              GIT_SSH_COMMAND = gitSsh;
              # nixos-rebuild shells out to nix, which needs the same key to read the
              # private input if it is not already in the store.
              NIX_SSHOPTS = "";
            };

            serviceConfig = {
              Type = "oneshot";
              # Root, because it ends in `nixos-rebuild switch`. The git and
              # flake-update steps drop to ${config.ogama.identity.user} via runuser, so nothing here
              # leaves root-owned objects in a user-owned .git — which would break
              # ordinary git use afterwards.
              User = "root";
            };

            script = ''
              set -eu

              cd ${configuration}

              distant=$(git ls-remote ${origin} refs/heads/${branch} | cut -f1)
              if [ -z "$distant" ]; then
                echo "branche ${branch} introuvable sur l'origine" >&2
                exit 1
              fi

              verrouille=$(jq -r '.nodes["lsi-web-interface"].locked.rev // ""' flake.lock)

              if [ "$distant" = "$verrouille" ]; then
                exit 0
              fi

              ${lib.optionalString requireCleanTree ''
                # Anything uncommitted other than flake.lock means someone is mid-work
                # in this tree. Rebuilding would deploy it, so stop and say why.
                sale=$(git status --porcelain -- . ':(exclude)flake.lock')
                if [ -n "$sale" ]; then
                  echo "arbre de travail modifié — déploiement ignoré :" >&2
                  echo "$sale" >&2
                  exit 0
                fi
              ''}

              echo "''${verrouille:-absent} -> $distant : mise à jour du verrou"

              # Snapshot the lock before touching it. The two rollbacks below restore
              # *this*, not `git checkout -- flake.lock`, because checkout reverts to
              # the last commit — which is a different thing entirely. This tree
              # routinely carries an uncommitted lock (a manual `nix flake update`, for
              # instance), and reverting to HEAD would silently discard it and move the
              # recorded revision further back than this tick ever moved it forward.
              #
              # Written by root into a file owned by ${config.ogama.identity.user}: `cp` truncates in
              # place rather than replacing the inode, so the ownership survives.
              avant=$(mktemp)
              cp flake.lock "$avant"
              trap 'rm -f "$avant"' EXIT

              # As the owning user: writing flake.lock and committing it as root would
              # hand root ownership of files and git objects in a user-owned tree.
              # This also puts the new input in the store, where the privileged
              # evaluation below finds it by narHash without needing the key itself —
              # the same dance flake.nix documents for calendar-syncer.
              #
              # `nix flake update` acts on the flake in the working directory, and
              # runuser (without -l) keeps the cwd set by the `cd` above. That is load
              # bearing: with a reset cwd it would update whatever flake is at /, or
              # nothing at all.
              # Absolute paths through runuser, not bare names: runuser drops to a
              # non-root user and resets PATH from login.defs rather than keeping the
              # unit's `path`, so `nix` and `git` are not reliably found on the other
              # side of it.
              runuser -u ${config.ogama.identity.user} -- env GIT_SSH_COMMAND="${gitSsh}" \
                ${config.nix.package}/bin/nix flake update lsi-web-interface

              # Build *before* committing the lock, and as ${config.ogama.identity.user} rather than as
              # root. Two separate reasons, both learned the hard way:
              #
              #   · root cannot evaluate this flake at all. Nix reads the working tree
              #     through libgit2, which refuses a repository owned by another user
              #     ("is not owned by current user", libgit2 error 7). Evaluating as
              #     the owner sidesteps it; root then only has to activate a closure
              #     that is already built, which needs no access to the repository.
              #
              #   · committing the lock first means a failed build leaves the lock
              #     pointing at the new revision, so the next tick finds
              #     locked == remote, exits early, and auto-deploy is silently wedged
              #     until someone reads the journal. Building first and putting the
              #     lock back on failure makes a transient failure retry by itself.
              if ! paquet=$(runuser -u ${config.ogama.identity.user} -- env GIT_SSH_COMMAND="${gitSsh}" \
                    ${config.nix.package}/bin/nix build --no-link --print-out-paths \
                    "${configuration}#nixosConfigurations.oserv.config.system.build.toplevel"); then
                echo "construction échouée — verrou remis en place, on réessaiera" >&2
                cp "$avant" flake.lock
                exit 1
              fi

              # The only privileged step, and the same two commands `nixos-rebuild
              # switch` ends with: register the generation, then activate it.
              # switch-to-configuration handles the bootloader itself.
              echo "activation de $paquet"
              ${config.nix.package}/bin/nix-env -p /nix/var/nix/profiles/system --set "$paquet"
              if ! "$paquet"/bin/switch-to-configuration switch; then
                echo "activation échouée — verrou remis en place, on réessaiera" >&2
                cp "$avant" flake.lock
                exit 1
              fi

              # Committed only once the new system is actually running. Doing it any
              # earlier is the same trap as committing before the build: a failed
              # activation would leave the lock pointing at the new revision, the next
              # tick would find locked == remote, exit early, and auto-deploy would be
              # wedged on a broken system with nobody retrying. Activation *does* fail
              # for ordinary reasons — a unit that will not start is one.
              #
              # Runs as ${config.ogama.identity.user}: git refuses to open a repository owned by someone
              # else ("detected dubious ownership"), and root is exempt only when
              # SUDO_UID says who it really is, which a systemd unit never sets. The
              # `git ls-remote <url>` above is unaffected because it never opens the
              # local repository.
              #
              # Guarded because `set -e` is on and `git commit` exits non-zero with
              # nothing staged, which an already-current lock would otherwise turn
              # into a failed unit.
              if runuser -u ${config.ogama.identity.user} -- ${pkgs.git}/bin/git diff --quiet HEAD -- flake.lock; then
                echo "flake.lock déjà à jour, rien à committer"
              else
                runuser -u ${config.ogama.identity.user} -- ${pkgs.git}/bin/git \
                  -c user.name="la-scene-interieure-maj" \
                  -c user.email="${config.ogama.identity.mail}" \
                  commit -q -m "chore(lsi): suit ${branch} ($distant)" -- flake.lock
              fi
            '';
          };

          systemd.timers.la-scene-interieure-maj = lib.mkIf autoFollow {
            description = "La Scène intérieure — vérifie ${branch} régulièrement";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "5min";
              # Slower than the old 2min: a tick can now mean a full Nix rebuild, so
              # there is no point asking more often than one can finish.
              OnUnitActiveSec = "10min";
              AccuracySec = "1min";
              Unit = "la-scene-interieure-maj.service";
            };
          };

          services.caddy.virtualHosts."https://${appHost}" = {
            extraConfig = ''
              # Milo (an external Caddy relay on another machine, not managed here)
              # fronts the public name and forwards here with Host rewritten to
              # ${appHost} so it matches this vhost — the app never sees the
              # browser's real Host. @sveltejs/adapter-node's CSRF check computes
              # its own "self" origin from that raw Host header (there is no ORIGIN
              # env var in this adapter-node version to override it), so a request
              # whose Origin is https://${pubAppHost} but whose Host says
              # ${appHost} gets rejected as cross-site on every POST — login
              # included. Overwriting Host here pins the app's self-origin to the
              # one name it should ever answer to, regardless of which name or
              # relay got the request here.
              reverse_proxy http://127.0.0.1:${toString web-port} {
                header_up Host ${pubAppHost}
              }
            '';
          };
          services.caddy.virtualHosts."https://${vitrineHost}" = {
            extraConfig = ''
              encode zstd gzip

              root * ${config.services.laSceneInterieure.vitrine.root}
              try_files {path} {path}/index.html {path}.html
              file_server
            '';
          };

          # Caddy would normally add this redirect itself, but it skips it when another
          # site already claims the same host on port 80 — and caddy.nix's
          # `http://*.${config.ogama.server.domain}` catch-all claims every subdomain, so an
          # http:// link to this name otherwise gets the catch-all's bare 404 and looks
          # like a dead service. An exact-host vhost outranks the wildcard. Same block
          # rustical.nix carries, for the same reason.
          services.caddy.virtualHosts."http://${vitrineHost}" = {
            extraConfig = ''
              redir https://{host}{uri} permanent
            '';
          };

          services.caddy.virtualHosts."http://${appHost}" = {
            extraConfig = ''
              redir https://{host}{uri} permanent
            '';
          };

        }
      );
    };

  flake.featureModules.home.laSceneInterieure = sharedOptions;
}
