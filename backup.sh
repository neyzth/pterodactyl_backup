#!/bin/bash

# Variables

API_URL=""  # URL de votre panel Pterodactyl
API_TOKEN=""                # Votre token API
BACKUP_DIR="/var/lib/pterodactyl/backups"    # Répertoire local des backups
REMOTE_DIR="/mnt/backup/"                     # Point de montage SMB
TRANSFER_LOG="/var/log/backup_transfer.log"  # Fichier log pour les transferts


# Créer le fichier de log s'il n'existe pas
touch "$TRANSFER_LOG"

# Fonction : Vérifier si un fichier a déjà été transféré
is_transferred() {
    grep -Fxq "$1" "$TRANSFER_LOG"
}

# Fonction : Récupérer la liste des serveurs
get_servers() {
    curl -s -X GET "$API_URL/api/client" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.data[].attributes.identifier'
}

# Fonction : Récupérer les backups pour un serveur donné
get_backups() {
    local server_id=$1
    curl -s -X GET "$API_URL/api/client/servers/$server_id/backups" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.data[].attributes | @base64'
}

# Fonction : Décoder et traiter les données JSON
decode_backup() {
    echo "$1" | base64 --decode | jq -r "$2"
}

# Transfert des backups
echo "Début du transfert des sauvegardes..."
for SERVER_ID in $(get_servers); do
    echo "Serveur détecté : $SERVER_ID"

    # Créer un dossier pour le serveur sur le partage SMB
    SERVER_DIR="$REMOTE_DIR/$SERVER_ID"
    mkdir -p "$SERVER_DIR"

    # Récupérer les backups pour ce serveur
    for BACKUP in $(get_backups "$SERVER_ID"); do
        BACKUP_UUID=$(decode_backup "$BACKUP" '.uuid')
        BACKUP_NAME=$(decode_backup "$BACKUP" '.name')

        # Vérifier si le backup a déjà été transféré
        if is_transferred "$BACKUP_UUID"; then
            echo "Déjà transféré : $BACKUP_UUID"
            continue
        fi

        # Construire le chemin du fichier backup local
        BACKUP_FILE="$BACKUP_DIR/$BACKUP_UUID.tar.gz"
        if [ -f "$BACKUP_FILE" ]; then
            # Transférer le fichier vers le dossier SMB
            echo "Transfert en cours : $BACKUP_FILE -> $SERVER_DIR"
            cp "$BACKUP_FILE" "$SERVER_DIR"

            # Vérifier si la copie a réussi
            if [ $? -eq 0 ]; then
                echo "Transfert réussi : $BACKUP_FILE"
                # Ajouter le fichier au log pour éviter de le retransférer
                echo "$BACKUP_UUID" >> "$TRANSFER_LOG"
            else
                echo "Erreur lors du transfert : $BACKUP_FILE"
            fi
        else
            echo "Fichier introuvable pour le backup : $BACKUP_UUID"
        fi
    done
done

# Confirmation
echo "Transfert terminé."
