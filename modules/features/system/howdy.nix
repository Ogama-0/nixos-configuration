{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.system.howdy.enable =
        lib.mkEnableOption "enable pam howdy for face recognition\
        for now, it's broken";
    };
in
{
  flake.featureModules.nixos.howdy =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.system.howdy.enable ({
        services.howdy = {

          enable = true;
          control = "sufficient";
          settings = {
            core = {
              abort_if_lid_closed = true;
              abort_if_ssh = false;
              detection_notice = false;
              disabled = false;
              no_confirmation = false;
              suppress_unknown = false;
              timeout_notice = true;
              use_cnn = false;
              workaround = "off";
            };
            debug = {
              end_report = false;
              gtk_stdout = false;
              verbose_stamps = false;
            };
            rubberstamps = {
              enabled = false;
              stamp_rules = "nod		5s		failsafe     min_distance=12";
            };
            snapshots = {
              save_failed = false;
              save_successful = false;
            };
            video = {
              certainty = 3.5;
              dark_threshold = 60;
              device_format = "v4l2";
              device_fps = -1;
              device_path = "/dev/video2";
              exposure = -1;
              force_mjpeg = false;
              frame_height = -1;
              frame_width = -1;
              max_height = 320;
              recording_plugin = "opencv";
              rotate = 0;
              timeout = 4;
              warn_no_device = true;
            };
          };
        };
        services.linux-enable-ir-emitter.enable = true;
      });
    };

  flake.featureModules.home.howdy = sharedOptions;
}
