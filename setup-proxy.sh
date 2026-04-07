#!/bin/bash

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd (gebruik sudo)."
   exit 1
fi

echo "-------------------------------------------------------"
echo "   Nginx Reverse Proxy & SSL Setup voor Ubuntu 24.04"
echo "-------------------------------------------------------"

# 1. Vragen om input
read -p "Welk domein moet er komen te staan? (bijv. gamepanel.nl): " DOMAIN
read -p "Naar welk adres moet dit worden doorgestuurd? (bijv. 127.0.0.1:30000 of node01.fivecloud.nl:30000): " TARGET

# Zorg dat de TARGET een http prefix heeft voor de config als het er niet staat
if [[ $TARGET != http* ]]; then
    PROXY_TARGET="http://$TARGET"
else
    PROXY_TARGET=$TARGET
fi

echo ""
echo "Bezig met installeren van benodigdheden (Nginx en Certbot)..."
apt update
apt install -y nginx certbot python3-certbot-nginx

# 2. Nginx Configuratie aanmaken
CONFIG_FILE="/etc/nginx/sites-available/$DOMAIN"

echo "Configuratie aanmaken in $CONFIG_FILE..."

cat <<EOF > $CONFIG_FILE
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    location / {
        proxy_pass $PROXY_TARGET;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Voor websockets (vaak nodig bij game panels)
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
    }
}
EOF

# 3. Linken naar sites-enabled
ln -sf $CONFIG_FILE /etc/nginx/sites-enabled/

# Verwijder default config als die nog bestaat om conflicten te voorkomen
rm -f /etc/nginx/sites-enabled/default

# Nginx testen en herstarten
echo "Nginx config testen..."
nginx -t
if [ $? -eq 0 ]; then
    systemctl restart nginx
    echo "Nginx is succesvol herstart."
else
    echo "Er zit een fout in de Nginx configuratie. Controleer je invoer."
    exit 1
fi

# 4. HTTPS (SSL) via Certbot
echo ""
echo "-------------------------------------------------------"
echo "   SSL Certificaat aanvragen via Let's Encrypt"
echo "-------------------------------------------------------"
echo "Zorg ervoor dat je DNS (A-record) van $DOMAIN al naar dit IP-adres verwijst!"
echo ""

# Voer certbot uit
certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos --register-unsafely-without-email

if [ $? -eq 0 ]; then
    echo ""
    echo "-------------------------------------------------------"
    echo "✅ SUCCES!"
    echo "Je website is nu beveiligd en bereikbaar op:"
    echo "https://$DOMAIN"
    echo "Alles wordt doorgestuurd naar: $PROXY_TARGET"
    echo "-------------------------------------------------------"
else
    echo ""
    echo "❌ SSL aanvraag is mislukt."
    echo "Waarschijnlijk staat de DNS nog niet goed of blokkeert een firewall poort 80/443."
fi
