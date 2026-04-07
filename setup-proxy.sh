#!/bin/bash

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo "❌ Voer dit script uit met sudo."
   exit 1
fi

# Functie voor het hoofdmenu
show_menu() {
    clear
    echo "======================================================="
    echo "   Nginx Proxy Manager - Ubuntu 24.04"
    echo "======================================================="
    echo "1) Nieuwe Proxy / Site toevoegen (incl. SSL)"
    echo "2) Bestaande Proxy / Site verwijderen"
    echo "3) Afsluiten"
    echo "======================================================="
    echo -n "Maak een keuze [1-3]: "
    read -r CHOICE < /dev/tty
}

# Functie om een nieuwe proxy aan te maken
create_proxy() {
    echo ""
    DOMAIN=""
    while [[ -z "$DOMAIN" ]]; do
        echo -n "👉 Welk domein moet de site krijgen? (bijv. gamepanel.nl): "
        read -r DOMAIN < /dev/tty
    done

    TARGET=""
    while [[ -z "$TARGET" ]]; do
        echo -n "👉 Naar welk adres:poort moet dit? (bijv. 127.0.0.1:30000): "
        read -r TARGET < /dev/tty
    done

    # Installatie benodigdheden
    echo "📦 Installeren van Nginx en Certbot (indien nodig)..."
    apt update -y && apt install -y nginx certbot python3-certbot-nginx

    # Firewall
    if ufw status | grep -q "Status: active"; then
        ufw allow 'Nginx Full'
    fi

    # Config aanmaken
    CONFIG_NAME="$DOMAIN.conf"
    CONFIG_FILE="/etc/nginx/sites-available/$CONFIG_NAME"

    if [[ $TARGET != http* ]]; then
        PROXY_TARGET="http://$TARGET"
    else
        PROXY_TARGET=$TARGET
    fi

    cat <<EOF > "$CONFIG_FILE"
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    location / {
        proxy_pass $PROXY_TARGET;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

    # Activeren
    ln -sf "$CONFIG_FILE" "/etc/nginx/sites-enabled/"
    rm -f /etc/nginx/sites-enabled/default

    if nginx -t; then
        systemctl reload nginx
        echo "✅ Nginx geconfigureerd."
    else
        echo "❌ Fout in Nginx configuratie. Controleer je invoer."
        return
    fi

    # SSL Certificaat
    echo "🔒 SSL Certificaat aanvragen..."
    certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email

    echo "✅ Klaar! https://$DOMAIN is nu actief."
    echo "Druk op ENTER om terug te gaan..."
    read -r < /dev/tty
}

# Functie om een proxy te verwijderen
delete_proxy() {
    echo ""
    echo "--- Bestaande configuraties ---"
    
    # Haal alle .conf bestanden op in sites-available
    cd /etc/nginx/sites-available/ || exit
    FILES=(*.conf)
    
    if [ "${FILES[0]}" == "*.conf" ]; then
        echo "Geen proxy configuraties gevonden."
        echo "Druk op ENTER om terug te gaan..."
        read -r < /dev/tty
        return
    fi

    # Toon de lijst met nummers
    for i in "${!FILES[@]}"; do
        echo "$((i+1))) ${FILES[$i]}"
    done
    echo "$(( ${#FILES[@]} + 1 ))) Annuleren"

    echo -n "Welk nummer wil je VERWIJDEREN? "
    read -r FILE_INDEX < /dev/tty

    # Controleer of keuze geldig is
    if [[ "$FILE_INDEX" -gt 0 && "$FILE_INDEX" -le "${#FILES[@]}" ]]; then
        SELECTED_FILE="${FILES[$((FILE_INDEX-1))]}"
        
        echo -n "Weet je zeker dat je $SELECTED_FILE wilt verwijderen? (y/n): "
        read -r CONFIRM < /dev/tty
        
        if [[ "$CONFIRM" == "y" ]]; then
            rm -f "/etc/nginx/sites-available/$SELECTED_FILE"
            rm -f "/etc/nginx/sites-enabled/$SELECTED_FILE"
            systemctl reload nginx
            echo "✅ $SELECTED_FILE is verwijderd."
        else
            echo "Verwijdering geannuleerd."
        fi
    else
        echo "Geannuleerd."
    fi

    echo "Druk op ENTER om terug te gaan..."
    read -r < /dev/tty
}

# Hoofdloop van het script
while true; do
    show_menu
    case $CHOICE in
        1) create_proxy ;;
        2) delete_proxy ;;
        3) exit 0 ;;
        *) echo "Ongeldige keuze" ;;
    esac
done
