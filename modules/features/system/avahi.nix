{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.system.avahi.enable = lib.mkEnableOption "mDNS service discovery on the local network";
    };
in
{
  flake.featureModules.nixos.avahi =
    { lib, config, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.system.avahi.enable (
        {
          services.avahi = {
            enable = true;
            nssmdns4 = true;
            openFirewall = true;
            publish = {
              enable = true;
              userServices = true;
            };

            # Advertises the samba "timemachine" share over Bonjour so it shows up
            # directly in macOS System Settings > Time Machine.
            extraServiceFiles = {
              smb = ''
                <?xml version="1.0" standalone='no'?><!--*-nxml-*-->
                <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
                <service-group>
                  <name replace-wildcards="yes">%h</name>
                  <service>
                    <type>_smb._tcp</type>
                    <port>445</port>
                  </service>
                  <service>
                    <type>_device-info._tcp</type>
                    <port>0</port>
                    <txt-record>model=MacSamba</txt-record>
                  </service>
                  <service>
                    <type>_adisk._tcp</type>
                    <port>9</port>
                    <txt-record>dk0=adVN=timemachine,adVF=0x82</txt-record>
                    <txt-record>sys=waMA=0,adVF=0x100</txt-record>
                  </service>
                </service-group>
              '';
            };
          };
        }
      );
    };

  flake.featureModules.home.avahi = sharedOptions;
}
