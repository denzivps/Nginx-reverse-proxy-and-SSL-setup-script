#!/bin/bash

# 1. Gegevens verzamelen (Er wordt nog niets aangepast)
clear
echo "======================================================="
echo "   Nginx Reverse Proxy Setup voor Ubuntu 24.04"
echo "======================================================="
echo ""

read -p "Stap 1: Welk domein moet de site krijgen? (bijv. gamepanel.nl): " DOMAIN
read -p "Stap 2: Wat is de huidige locatie/poort? (bijv. localhost:30000): " TARGET

# Controleer of input leeg is
if [[ -z "$DOMAIN" || -z "$TARGET" ]]; then
    echo "❌ Fout: Je moet beide velden invullen!"
    exit 1
fi

echo ""
echo "Ingevoerde gegevens:"
echo "Domein: $DOMAIN"
echo "Target: $TARGET"
echo "Config bestand: /etc/nginx/sites-available/$DOMAIN"
echo ""
read -p "Klopt dit? Druk op [ENTER] om de installatie te starten..."

# 2. Installatie van benodigdheden
echo "------- Bezig met installeren van Nginx en Certbot -------"
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx

# 3. Firewall instellen (UFW)
echo "------- Firewall controleren -------"
# Check of UFW actief is, zo ja, sta Nginx toe
if sudo ufw status | grep -q "Status: active"; then
    echo "Firewall is actief, poorten 80 en 443 worden geopend..."
    sudo ufw allow 'Nginx Full'
else
    echo "Firewall staat uit, geen aanpassing nodig."
fi

# 4. Nginx Configuratie aanmaken met de domeinnaam als bestandsnaam
echo "------- Nginx config aanmaken -------"
CONFIG_FILE="/etc/nginx/sites-available/$DOMAIN"

# Zorg dat TARGET http:// bevat als het er niet in staat
if [[ $TARGET != http* ]]; then
    PROXY_TARGET="http://$TARGET"
else
    PROXY_TARGET=$TARGET
fi

sudo bash -c "cat <<EOF > $CONFIG_FILE
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    location / {
        proxy_pass $PROXY_TARGET;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket ondersteuning (belangrijk voor game panels)
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
    }
}
EOF"

# 5. Configureren en testen
echo "------- Configureren en testen -------"

# Linken van sites-available naar sites-enabled
sudo ln -sf "$CONFIG_FILE" "/etc/nginx/sites-enabled/"

# Test de nginx configuratie op syntax fouten
if sudo nginx -t; then
    echo "Nginx configuratie is correct. Herstarten..."
    sudo systemctl reload nginx
else
    echo "❌ Er zit een fout in de Nginx config. We draaien de wijziging niet door."
    exit 1
fi

# 6. SSL Certificaat aanvragen
echo "------- SSL Certificaat aanvragen (Let's Encrypt) -------"
echo "Zorg dat je DNS (A-record) al naar dit IP-adres verwijst!"

sudo certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email

# Afronding
echo ""
echo "======================================================="
echo "✅ KLAAR!"
echo "Website: https://$DOMAIN"
echo "Configuratie: /etc/nginx/sites-available/$DOMAIN"
echo "Alles is beveiligd met SSL en de firewall is bijgewerkt."
echo "======================================================="
