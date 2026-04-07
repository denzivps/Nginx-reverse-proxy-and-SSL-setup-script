#!/bin/bash

# Controleer of script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo "❌ Voer dit script uit met sudo: sudo ./setup-proxy.sh"
   exit 1
fi

clear
echo "======================================================="
echo "   Nginx Reverse Proxy Setup voor Ubuntu 24.04"
echo "======================================================="

# Loop voor Domeinnaam
DOMAIN=""
while [[ -z "$DOMAIN" ]]; do
    echo -n "👉 Stap 1: Welk domein moet de site krijgen? (bijv. gamepanel.nl): "
    read -r DOMAIN
    if [[ -z "$DOMAIN" ]]; then
        echo "   Fout: Domein mag niet leeg zijn!"
    fi
done

# Loop voor Target
TARGET=""
while [[ -z "$TARGET" ]]; do
    echo -n "👉 Stap 2: Naar welk adres/poort moet dit? (bijv. localhost:30000): "
    read -r TARGET
    if [[ -z "$TARGET" ]]; then
        echo "   Fout: Adres mag niet leeg zijn!"
    fi
done

echo ""
echo "-------------------------------------------------------"
echo "Controleer de gegevens:"
echo "Domein:         $DOMAIN"
echo "Doorsturen naar: $TARGET"
echo "Config bestand:  /etc/nginx/sites-available/$DOMAIN"
echo "-------------------------------------------------------"
echo -n "Druk op [ENTER] om de installatie te starten of CTRL+C om te stoppen..."
read -r

echo ""
echo "🚀 Starten met de installatie..."

# 1. Installatie van benodigdheden
echo "📦 Installeren van Nginx en Certbot..."
apt update -y && apt install -y nginx certbot python3-certbot-nginx

# 2. Firewall instellen (UFW)
echo "🛡️  Firewall controleren..."
if ufw status | grep -q "Status: active"; then
    echo "   Firewall is actief, poorten 80 en 443 worden geopend..."
    ufw allow 'Nginx Full'
else
    echo "   Firewall staat uit, geen actie nodig."
fi

# 3. Nginx Configuratie aanmaken
echo "📝 Nginx config aanmaken voor $DOMAIN..."
CONFIG_FILE="/etc/nginx/sites-available/$DOMAIN"

# Zorg dat TARGET http:// bevat als het er niet in staat
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

        # WebSocket ondersteuning
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

# 4. Activeren en Testen
echo "🔗 Configureren en testen..."
ln -sf "$CONFIG_FILE" "/etc/nginx/sites-enabled/"

# Test de nginx configuratie
if nginx -t; then
    echo "   Configuratie is correct. Nginx herladen..."
    systemctl reload nginx
else
    echo "❌ Er zit een fout in de Nginx config. We breken de SSL aanvraag af."
    exit 1
fi

# 5. SSL Certificaat via Certbot
echo "🔒 SSL Certificaat aanvragen via Let's Encrypt..."
echo "Let op: Je DNS moet al verwijzen naar dit IP!"

certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email

if [ $? -eq 0 ]; then
    echo ""
    echo "======================================================="
    echo "✅ ALLES IS VOLTOOID!"
    echo "Website: https://$DOMAIN"
    echo "De site wordt doorgestuurd naar: $PROXY_TARGET"
    echo "De firewall staat goed en SSL is actief."
    echo "======================================================="
else
    echo ""
    echo "⚠️  SSL aanvraag mislukt. Controleer of je DNS goed staat."
    echo "Je kunt SSL later handmatig proberen met: sudo certbot --nginx"
fi
