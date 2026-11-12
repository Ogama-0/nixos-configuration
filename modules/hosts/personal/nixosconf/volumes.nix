{ ... }: {
  boot.supportedFilesystems = [ "ntfs" ];

  fileSystems."/mnt/windows" = {
    device = "/dev/disk/by-uuid/6AB04E5BB04E2E3F";
    fsType = "ntfs";
    options = [ "rw" "uid=1000" "gid=100" "umask=022" ];
  };
}
