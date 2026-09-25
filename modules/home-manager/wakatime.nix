{ config, lib, ... }: {

  sops.secrets.wakatime_api_key.sopsFile = ../../sops/wakatime.yaml;

  home.activation.wakatimeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run cat > "$HOME/.wakatime.cfg" <<EOF
[settings]
api_key = $(cat ${config.sops.secrets.wakatime_api_key.path})
EOF
  '';
}
