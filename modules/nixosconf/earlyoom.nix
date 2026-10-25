{ ... }:
{
  services.earlyoom = {
    enable = true;

    # Percentages of total RAM. This machine has 13G and no swap, so at the
    # old 2% earlyoom only woke up with ~260M left - late enough that the
    # kernel OOM killer regularly got there first, and the kernel picks purely
    # by RSS, which on a desktop means the shell and the compositor. Acting at
    # 8% leaves a gigabyte of headroom to choose a victim on purpose; the
    # SIGKILL stage stays lower so something that ignores SIGTERM is still
    # caught.
    freeMemThreshold = 8;
    freeMemKillThreshold = 4;
    freeSwapThreshold = 2;

    # Notifications are emitted on the SYSTEM bus, because earlyoom is root.
    # systembus-notify is the user-side relay that forwards them to the
    # session's notification daemon - here the laser bar's own server - and
    # the module enables it along with this.
    enableNotifications = true;

    # Two things to know before touching these patterns.
    #
    # They match /proc/pid/comm, which is 15 characters, and a nixpkgs wrapper
    # renames the process: the shell runs as ".quickshell-wra" and the browser
    # as ".zen-beta-wrapp". The previous `^(X|init|...|quickshell)$` therefore
    # matched nothing at all - no truncated, dot-prefixed name can equal its
    # own full name. earlyoom's regexec is unanchored, so plain substrings are
    # the form that survives both the prefix and the cut.
    #
    # And they must carry no quotes of their own: extraArgs goes through
    # lib.escapeShellArgs, so the `'` in the old value ended up as the first
    # character of the regex.
    extraArgs = [
      # Never. Freeing memory by killing the compositor or the shell loses the
      # desktop the memory was for - and unlike --avoid, --ignore is absolute.
      "--ignore"
      "(quickshell|sway|systemd|dbus-broker|greetd)"

      # Last resorts rather than never: the session's plumbing and the
      # terminal you are probably watching the build in. Note this protects
      # the terminal, not what runs inside it - a compiler eating the machine
      # is still fair game, which is the point.
      "--avoid"
      "(Xwayland|alacritty|pipewire|wireplumber|sshd|kdeconnect|swayidle|darkman)"

      # Big GUI software that is cheap to lose: a tab reloads, gimp and
      # thunderbird reopen, a lab restarts.
      #
      # The browser entries are its CHILDREN, not the browser: Firefox names
      # a tab "Web Content" or "Isolated Web Co", and those are what should
      # go. `.zen-beta-wrapp` is deliberately absent - its oom_score is 838
      # against the fattest tab's 833, so preferring both means the parent
      # wins and the whole browser dies to reclaim one tab's worth of memory.
      # Unpreferred it is still an ordinary candidate, just only after every
      # tab has been tried. Chromium is the exception: parent and renderers
      # share the comm "chrome", and there is nothing in the name to tell
      # them apart - Chrome's own higher oom_score_adj on renderers is what
      # sorts that out.
      #
      # The browser's plumbing (RDD, Socket Process, forkserver) is left out
      # too: a few dozen MiB each, and taking one down breaks the browser as
      # surely as killing the parent would.
      #
      # This is also why -g is gone: killing the process group would take the
      # whole browser down with any one of its tabs.
      "--prefer"
      "(Web Content|Isolated Web|Isolated Servic|WebExtensions|chrome|chromium|thunderbird|gimp|deezer|joplin|vesktop|electron|gns3|dynamips|vpcs|ubridge|qemu-system)"
    ];
  };
}
