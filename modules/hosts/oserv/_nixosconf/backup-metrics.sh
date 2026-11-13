# Collects the backup facts no exporter on this host knows about, and writes
# them to a Prometheus textfile that node-exporter picks up.
#
# node-exporter's systemd collector can say whether borgbackup-job-*.service is
# failed and when its timer last fired, but not whether an archive actually
# landed, how old the newest one is, or how much disk the repository eats. Time
# Machine is worse: it is a Samba share, so nothing on this host observes it at
# all. Both are read here directly from the filesystem.
#
# Inputs (set by backup-metrics.nix, not by hand):
#   BACKUP_REPOS_FILE  file of "<name><TAB><path>" lines, one per borg repository
#   TIMEMACHINE_ROOT   directory holding the *.sparsebundle bundles
#   TEXTFILE_DIR       node-exporter's --collector.textfile.directory
#   BORG_BASE_DIR      where borg may keep its cache and config
#
# It needs to run as root: borg repositories are mode 0700 root-owned inside.

started=$(date +%s)

# Written under the collector directory, then renamed into place: the textfile
# collector reads *.prom whenever it feels like it, and would happily serve a
# half-written file. The temp name deliberately does not end in .prom.
tmp=$(mktemp "$TEXTFILE_DIR/.backups.prom.XXXXXX")
trap 'rm -f "$tmp"' EXIT
chmod 0644 "$tmp"

# These repositories are unencrypted (encryption.mode = "none" in
# backup-server.nix), which borg refuses to touch non-interactively without
# this.
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

# A backup job holding the repository lock is the normal state of affairs at
# 03:00, not an error. Wait briefly, then give up and report the repo as
# uncollected rather than failing the whole run.
export BORG_LOCK_WAIT=15

repo_names=()
declare -A repo_ok repo_last repo_count repo_size

# Reads one repository. Only `borg list` is used, which reads the manifest and
# nothing else — `borg info` would pull in the chunk cache, which is both slow
# and contended with a running backup. Size therefore comes from du, which is
# also the more honest number: it is what the pool actually spends.
collect_repo() {
    local name=$1 path=$2
    local json archives last size

    repo_names+=("$name")
    repo_ok[$name]=0
    repo_count[$name]=0
    repo_size[$name]=0

    if json=$(borg list --json "$path" 2>/dev/null); then
        archives=$(jq -r '.archives | length' <<<"$json")
        repo_count[$name]=$archives
        repo_ok[$name]=1

        if [ "$archives" -gt 0 ]; then
            # Lexicographic max over ISO-8601 strings is the chronological max,
            # so this does not depend on borg's archive ordering.
            last=$(jq -r '[.archives[].start] | max' <<<"$json")
            repo_last[$name]=$(date -d "$last" +%s)
        fi
    fi

    if size=$(du -s -B1 "$path" 2>/dev/null | cut -f1); then
        repo_size[$name]=$size
    fi
}

tm_names=()
declare -A tm_last tm_size

# One walk per sparsebundle yields both numbers: the newest mtime anywhere
# inside it (Time Machine rewrites band files in place, so the bundle's own
# mtime lies) and the disk it occupies. %b is 512-byte blocks actually used,
# which is what matters on a share with a 500G cap.
collect_timemachine() {
    local root=$1
    local sb machine stats

    [ -d "$root" ] || return 0

    shopt -s nullglob
    for sb in "$root"/*.sparsebundle; do
        [ -d "$sb" ] || continue
        machine=$(basename "$sb" .sparsebundle)
        stats=$(find "$sb" -type f -printf '%T@ %b\n' 2>/dev/null |
            awk '{ if ($1 > m) m = $1; s += $2 } END { printf "%d %d\n", m, s * 512 }')
        tm_names+=("$machine")
        tm_last[$machine]=${stats%% *}
        tm_size[$machine]=${stats##* }
    done
    shopt -u nullglob
}

while IFS=$'\t' read -r repo_name repo_path; do
    [ -n "$repo_name" ] || continue
    collect_repo "$repo_name" "$repo_path"
done <"$BACKUP_REPOS_FILE"

collect_timemachine "$TIMEMACHINE_ROOT"

gauge() {
    printf '# HELP %s %s\n# TYPE %s gauge\n' "$1" "$2" "$1"
}

{
    gauge borg_repo_collect_success \
        'Whether this run could read the repository (0 means borg failed or the lock was held).'
    for n in "${repo_names[@]}"; do
        printf 'borg_repo_collect_success{repo="%s"} %s\n' "$n" "${repo_ok[$n]}"
    done

    # Deliberately absent for a repository with no archives yet, so panels show
    # "no data" instead of an age measured from the epoch.
    gauge borg_repo_last_archive_timestamp_seconds \
        'Start time of the newest archive in the repository.'
    for n in "${repo_names[@]}"; do
        [ -n "${repo_last[$n]:-}" ] || continue
        printf 'borg_repo_last_archive_timestamp_seconds{repo="%s"} %s\n' "$n" "${repo_last[$n]}"
    done

    gauge borg_repo_archive_count 'Number of archives in the repository.'
    for n in "${repo_names[@]}"; do
        printf 'borg_repo_archive_count{repo="%s"} %s\n' "$n" "${repo_count[$n]}"
    done

    gauge borg_repo_disk_usage_bytes 'Disk occupied by the repository directory.'
    for n in "${repo_names[@]}"; do
        printf 'borg_repo_disk_usage_bytes{repo="%s"} %s\n' "$n" "${repo_size[$n]}"
    done

    gauge timemachine_last_backup_timestamp_seconds \
        'Newest mtime inside the machine sparsebundle.'
    for n in "${tm_names[@]}"; do
        printf 'timemachine_last_backup_timestamp_seconds{machine="%s"} %s\n' "$n" "${tm_last[$n]}"
    done

    gauge timemachine_size_bytes 'Disk occupied by the machine sparsebundle.'
    for n in "${tm_names[@]}"; do
        printf 'timemachine_size_bytes{machine="%s"} %s\n' "$n" "${tm_size[$n]}"
    done

    gauge backup_collector_last_run_timestamp_seconds \
        'When this collector last completed. Everything above is as stale as this.'
    printf 'backup_collector_last_run_timestamp_seconds %s\n' "$(date +%s)"

    gauge backup_collector_duration_seconds 'How long the last collection took.'
    printf 'backup_collector_duration_seconds %s\n' "$(($(date +%s) - started))"
} >"$tmp"

mv "$tmp" "$TEXTFILE_DIR/backups.prom"
trap - EXIT
