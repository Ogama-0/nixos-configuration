function wgup
    set confname oscar
    set devconfname oscar-dev
    set backupconfname backup
    set devbackupconfname backup-dev

    # Correction de la déclaration des options dans argparse
    argparse d/dev b/backup -- $argv

    if set -q _flag_dev
        if set -q _flag_backup
            sudo systemctl start wg-quick-$devbackupconfname # Mode développement + backup
        else
            sudo systemctl start wg-quick-$devconfname # Mode développement seul
        end
    else
        if set -q _flag_backup
            sudo systemctl start wg-quick-$backupconfname # Mode backup seul
        else
            sudo systemctl start wg-quick-$confname # Mode normal
        end
    end
    # sudo mount -t cifs //192.168.10.51/general_storage $PATH_NAS -o username=oscar,password=mdpelo,uid=$(id -u),gid=$(id -g)
end
