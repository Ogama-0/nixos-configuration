function wgdn
    # sudo umount $PATH_NAS/
    # Récupérer la configuration WireGuard active
    set confname (sudo wg | grep interface | sed 's/.* //')

    # Vérifier si une configuration est active
    if test -n "$confname"
        sudo systemctl stop wg-quick-$confname
        echo "Configuration '$confname' arrêtée avec succès."
    else
        echo "Aucune configuration WireGuard active trouvée."
    end
end
