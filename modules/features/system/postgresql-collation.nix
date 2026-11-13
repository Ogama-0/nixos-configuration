{ ... }:
let
  # Defaults to following services.postgresql.enable rather than being a host flag: it must apply wherever postgres runs, and forgetting it is how ensureDatabases silently stops working after a glibc bump.
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { config, lib, ... }:
    {
      options.ogama.system.postgresqlCollation.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.services.postgresql.enable;
        defaultText = lib.literalExpression "config.services.postgresql.enable";
        description = "the collation-version fixup that unblocks ensureDatabases after a glibc bump";
      };
    };
in
{
  flake.featureModules.nixos.postgresqlCollation =
    { config, lib, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.system.postgresqlCollation.enable (
        let
          psql = "${config.services.postgresql.package}/bin/psql";

          # The databases Postgres itself owns. All three are empty — template0 and
          # template1 are the prototypes every new database is cloned from, and
          # "postgres" is the default admin connection target. Nothing of yours lives
          # in them, so there are no text indexes that could have been built in the
          # wrong order: refreshing their recorded collation version asserts nothing
          # and risks nothing.
          systeme = [ "template0" "template1" "postgres" ];

          # Which of them can actually be refreshed. ALTER DATABASE ... REFRESH
          # COLLATION VERSION throws "invalid collation version change" the moment the
          # recorded version and the real one disagree about *existing*: a database in
          # the C/POSIX locale has no collation version at all, so
          # pg_database_collation_actual_version() is NULL for it, and refreshing a
          # recorded version to NULL (or vice versa) is refused outright. Picking the
          # rows first is what keeps that case from killing the unit — it is precisely
          # what the first version of this module got wrong.
          aRafraichir = ''
            select datname from pg_database
             where datname in (${lib.concatMapStringsSep ", " (d: "'${d}'") systeme})
               and datcollversion is not null
               and pg_database_collation_actual_version(oid) is not null
               and datcollversion <> pg_database_collation_actual_version(oid)
             order by datname
          '';
        in
        {
          # Postgres sorts text through glibc's strcoll(), so a text index is
          # physically ordered by whatever glibc said when it was built. Each database
          # records that library version (pg_database.datcollversion) and complains
          # when the running glibc disagrees — which happens every time a nixpkgs bump
          # moves glibc, here 2.40 -> 2.42.
          #
          # For an ordinary database that is a WARNING. For a *template* it is a hard
          # ERROR, because CREATE DATABASE clones the template, and copying
          # possibly-misordered indexes into a new database is a correctness problem.
          # So this is not cosmetic: until the templates are refreshed,
          # `services.postgresql.ensureDatabases` cannot create anything at all, and
          # the whole activation fails. That is how adding la-scene-interieure.nix
          # turned a 3-day-old silent warning into a failing switch.
          #
          # Only the system databases are touched here, and only with REFRESH (never
          # REINDEX): they hold no data, so there is nothing to rebuild. Databases with
          # real content are deliberately left alone — see the reindex unit below.
          systemd.services.postgresql-collation-refresh = {
            description = "Rafraîchit la version de collation des bases système";

            # Must land between "the server is up" and "ensureDatabases runs", because
            # it is precisely what unblocks the CREATE DATABASE that postgresql-setup
            # performs.
            #
            # wantedBy, deliberately not requiredBy. This unit can only ever help, so it
            # must never be able to block the thing it exists to unblock — with
            # requiredBy, one failure here stopped postgresql-setup, which left the lsi
            # database uncreated, which put the app in a restart loop. Ordering still
            # holds via `before`; a failure now just means postgresql-setup runs anyway
            # and reports its own, clearer error.
            after = [ "postgresql.service" ];
            requires = [ "postgresql.service" ];
            before = [ "postgresql-setup.service" ];
            wantedBy = [ "postgresql-setup.service" "multi-user.target" ];

            serviceConfig = {
              Type = "oneshot";
              User = "postgres";
              Group = "postgres";
              RemainAfterExit = false;
            };

            # Idempotent twice over: the query only returns rows that genuinely differ,
            # and refreshing a database whose version already matches would be a no-op
            # NOTICE anyway. ALTER DATABASE does not connect to its target, which is what
            # lets template0 be refreshed at all — it has datallowconn = false and
            # cannot be connected to.
            #
            # No `set -e` around the loop, and no ON_ERROR_STOP spanning it: a database
            # that cannot be refreshed is reported and skipped, never fatal.
            script = ''
              set -u

              bases=$(${psql} -At -d postgres -c "${aRafraichir}")

              if [ -z "$bases" ]; then
                echo "aucune base système à rafraîchir"
              fi

              for db in $bases; do
                echo "rafraîchit la collation de $db"
                ${psql} -d postgres -c "ALTER DATABASE \"$db\" REFRESH COLLATION VERSION" \
                  || echo "échec sur $db — on continue" >&2
              done

              # Purement informatif, et la raison d'être de l'unité : si template1 reste
              # en désaccord, CREATE DATABASE refusera et ensureDatabases avec lui.
              reste=$(${psql} -At -d postgres -c "
                select datname || ' : ' || coalesce(datcollversion, '(aucune)') || ' vs '
                       || coalesce(pg_database_collation_actual_version(oid), '(aucune)')
                  from pg_database
                 where datcollversion is distinct from pg_database_collation_actual_version(oid)
                 order by datname")
              if [ -n "$reste" ]; then
                echo "encore en désaccord (REINDEX puis REFRESH, cf. postgresql-collation-reindex) :" >&2
                echo "$reste" >&2
              fi

              exit 0
            '';
          };

          # The other half, and the reason this is a separate unit rather than more
          # lines above: databases with real content may genuinely need their indexes
          # rebuilt, and that is a decision about downtime, not a configuration.
          #
          # REINDEX takes ACCESS EXCLUSIVE locks and runs for as long as the data takes
          # — on Immich's library that is minutes. Wiring it into activation would mean
          # a `nixos-rebuild switch` that hangs unpredictably with the photo library
          # locked, so it is declared but never started automatically:
          #
          #   sudo systemctl start postgresql-collation-reindex
          #
          # Stop the services using those databases first. Until this is run, the only
          # exposure is that if glibc 2.42 did change sort order for this locale, text
          # index lookups can silently miss rows — REFRESH alone would hide that
          # forever, which is exactly why it is not applied to these databases.
          systemd.services.postgresql-collation-reindex = {
            description = "Reconstruit les index et rafraîchit la collation (manuel)";

            after = [ "postgresql.service" ];
            requires = [ "postgresql.service" ];
            # No wantedBy / requiredBy on purpose: nothing ever starts this but you.

            serviceConfig = {
              Type = "oneshot";
              User = "postgres";
              Group = "postgres";
            };

            # Discovered at runtime rather than listed here, so a database added later
            # is not silently skipped. datallowconn excludes template0, which cannot be
            # connected to and needs no reindex anyway (it is empty by definition).
            script = ''
              set -eu
              bases=$(${psql} -At -d postgres -c \
                "select datname from pg_database where datallowconn and not datistemplate")

              for db in $bases; do
                echo "== $db : reconstruction des index"
                ${psql} -v ON_ERROR_STOP=1 -d "$db" -c "REINDEX DATABASE \"$db\""
                ${psql} -v ON_ERROR_STOP=1 -d postgres \
                  -c "ALTER DATABASE \"$db\" REFRESH COLLATION VERSION"
              done
            '';
          };
        }
      );
    };

  flake.featureModules.home.postgresqlCollation = sharedOptions;
}
