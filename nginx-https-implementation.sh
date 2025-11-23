#!/bin/bash
# =============================================================================
# TP4 Sécurité Web - Configuration HTTPS complète sur NGINX (VERSION AMÉLIORÉE)
# Domaine : secure-domain.ma
# Système : Linux Mint / Ubuntu / Debian
# Certificat trusted (mkcert) avec vérifications complètes
# Auteur : Version améliorée avec gestion d'erreurs robuste
# =============================================================================

set -euo pipefail  # Mode strict : arrêt sur erreur + variables non définies

# Configuration
DOMAIN="secure-domain.ma"
WWW="www.secure-domain.ma"
IP="127.0.0.1"
CERT_DIR="/etc/ssl/certs"
KEY_DIR="/etc/ssl/private"
WEB_ROOT="/var/www/html"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"

# Couleurs pour output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage
print_step() {
    echo -e "${BLUE}[${1}]${NC} ${2}"
}

print_success() {
    echo -e "   ${GREEN}✓${NC} ${1}"
}

print_warning() {
    echo -e "   ${YELLOW}⚠${NC} ${1}"
}

print_error() {
    echo -e "   ${RED}✗${NC} ${1}"
}

# Fonction de vérification root
check_root() {
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        print_error "Ce script nécessite les privilèges sudo"
        exit 1
    fi
}

# Fonction de nettoyage en cas d'erreur
cleanup_on_error() {
    print_error "Une erreur est survenue. Nettoyage..."
    sudo systemctl stop nginx 2>/dev/null || true
    exit 1
}

trap cleanup_on_error ERR

echo "=========================================================="
echo "  Configuration HTTPS NGINX - secure-domain.ma (TP4)"
echo "  Version améliorée avec vérifications complètes"
echo "=========================================================="
echo ""

# Vérification root
check_root

# =============================================================================
# ÉTAPE 1 : Configuration du domaine local
# =============================================================================
print_step "1/10" "Configuration du domaine dans /etc/hosts..."

if grep -q "^${IP}[[:space:]].*${DOMAIN}" /etc/hosts; then
    print_warning "Domaine déjà présent dans /etc/hosts"
else
    echo "${IP} ${DOMAIN} ${WWW}" | sudo tee -a /etc/hosts > /dev/null
    print_success "${DOMAIN} et ${WWW} ajoutés dans /etc/hosts"
fi

# Vérification
if ping -c 1 "${DOMAIN}" &> /dev/null; then
    print_success "Résolution DNS locale fonctionne"
else
    print_warning "Ping échoué (normal avec certains pare-feu)"
fi

# =============================================================================
# ÉTAPE 2 : Installation des dépendances
# =============================================================================
print_step "2/10" "Installation de NGINX et outils SSL..."

sudo apt update
sudo apt install -y nginx openssl libnss3-tools curl wget ca-certificates

# Vérification des installations
if command -v nginx &> /dev/null && command -v openssl &> /dev/null; then
    print_success "NGINX $(nginx -v 2>&1 | cut -d'/' -f2) et OpenSSL installés"
else
    print_error "Échec de l'installation des dépendances"
    exit 1
fi

# =============================================================================
# ÉTAPE 3 : Installation de mkcert
# =============================================================================
print_step "3/10" "Installation de mkcert (certificats trusted)..."

if ! command -v mkcert &> /dev/null; then
    MKCERT_VERSION="v1.4.4"
    MKCERT_URL="https://github.com/FiloSottile/mkcert/releases/download/${MKCERT_VERSION}/mkcert-${MKCERT_VERSION}-linux-amd64"
    
    wget -q --show-progress "${MKCERT_URL}" -O /tmp/mkcert
    sudo install /tmp/mkcert /usr/local/bin/mkcert
    rm /tmp/mkcert
    print_success "mkcert ${MKCERT_VERSION} installé"
else
    print_success "mkcert déjà installé ($(mkcert -version 2>&1 | head -n1))"
fi

# Installation de l'autorité de certification locale
print_step "3.5/10" "Installation de l'autorité de certification locale..."
mkcert -install
if [[ $? -eq 0 ]]; then
    print_success "CA locale installée avec succès"
else
    print_warning "CA déjà installée"
fi

print_warning "⚠️  IMPORTANT : Redémarre tous tes navigateurs pour reconnaître le CA"

# =============================================================================
# ÉTAPE 4 : Génération du certificat SSL
# =============================================================================
print_step "4/10" "Génération du certificat SSL trusted avec mkcert..."

# Génération dans /tmp pour éviter les problèmes de permissions
cd /tmp
rm -f ${DOMAIN}*.pem 2>/dev/null || true

echo "Génération du certificat pour : ${DOMAIN}, ${WWW}, localhost, 127.0.0.1, ::1"
mkcert "${DOMAIN}" "${WWW}" localhost 127.0.0.1 ::1

# Détection automatique des fichiers générés
CERT_FILE=$(ls -1 ${DOMAIN}*.pem 2>/dev/null | grep -v "key" | head -n1)
KEY_FILE=$(ls -1 ${DOMAIN}*key.pem 2>/dev/null | head -n1)

if [[ -z "${CERT_FILE}" ]] || [[ -z "${KEY_FILE}" ]]; then
    print_error "Échec de la génération du certificat"
    ls -la ${DOMAIN}*.pem 2>/dev/null || true
    exit 1
fi

# Copie sécurisée des certificats
sudo mkdir -p "${CERT_DIR}" "${KEY_DIR}"
sudo cp "${CERT_FILE}" "${CERT_DIR}/${DOMAIN}.crt"
sudo cp "${KEY_FILE}" "${KEY_DIR}/${DOMAIN}.key"
sudo chmod 644 "${CERT_DIR}/${DOMAIN}.crt"
sudo chmod 600 "${KEY_DIR}/${DOMAIN}.key"
sudo chown root:root "${CERT_DIR}/${DOMAIN}.crt" "${KEY_DIR}/${DOMAIN}.key"

# Nettoyage
rm -f ${DOMAIN}*.pem
cd - > /dev/null

print_success "Certificat installé dans ${CERT_DIR}/"
print_success "Clé privée sécurisée dans ${KEY_DIR}/"

# Vérification du certificat
if openssl x509 -in "${CERT_DIR}/${DOMAIN}.crt" -noout -text | grep -q "${DOMAIN}"; then
    print_success "Certificat valide pour ${DOMAIN}"
else
    print_error "Certificat invalide ou corrompu"
    exit 1
fi

# =============================================================================
# ÉTAPE 5 : Génération des paramètres Diffie-Hellman
# =============================================================================
print_step "5/10" "Génération du groupe Diffie-Hellman (2048 bits)..."

if [[ ! -f /etc/nginx/dhparam.pem ]]; then
    echo "Génération en cours (cela peut prendre 1-2 minutes)..."
    sudo openssl dhparam -out /etc/nginx/dhparam.pem 2048
    print_success "dhparam.pem généré (améliore la sécurité)"
else
    print_success "dhparam.pem déjà existant"
fi

# =============================================================================
# ÉTAPE 6 : Création de la page web
# =============================================================================
print_step "6/10" "Création de la page web de test..."

sudo tee "${WEB_ROOT}/${DOMAIN}.html" > /dev/null <<'EOF'
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>TP4 Sécurité Web - HTTPS Configuré</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            padding: 50px;
            max-width: 600px;
            text-align: center;
        }
        .lock-icon {
            font-size: 80px;
            margin-bottom: 20px;
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0%, 100% { transform: scale(1); }
            50% { transform: scale(1.1); }
        }
        h1 {
            color: #28a745;
            margin-bottom: 20px;
            font-size: 2em;
        }
        .info {
            background: #f8f9fa;
            border-left: 4px solid #28a745;
            padding: 15px;
            margin: 20px 0;
            text-align: left;
            border-radius: 5px;
        }
        .info-item {
            margin: 10px 0;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .info-label {
            font-weight: bold;
            color: #495057;
        }
        .info-value {
            color: #6c757d;
            font-family: 'Courier New', monospace;
            background: white;
            padding: 5px 10px;
            border-radius: 4px;
        }
        .badge {
            display: inline-block;
            padding: 5px 15px;
            background: #28a745;
            color: white;
            border-radius: 20px;
            font-size: 0.9em;
            margin: 5px;
        }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 2px solid #e9ecef;
            color: #6c757d;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="lock-icon">🔒</div>
        <h1>HTTPS Configuré avec Succès !</h1>
        <p style="color: #6c757d; margin-bottom: 30px;">
            Ton serveur NGINX est maintenant sécurisé avec un certificat SSL trusted
        </p>
        
        <div class="info">
            <div class="info-item">
                <span class="info-label">Domaine :</span>
                <span class="info-value" id="domain">secure-domain.ma</span>
            </div>
            <div class="info-item">
                <span class="info-label">Protocole :</span>
                <span class="info-value">HTTPS / TLS 1.3</span>
            </div>
            <div class="info-item">
                <span class="info-label">Certificat :</span>
                <span class="info-value">mkcert (trusted)</span>
            </div>
            <div class="info-item">
                <span class="info-label">Serveur :</span>
                <span class="info-value">NGINX</span>
            </div>
        </div>

        <div>
            <span class="badge">✓ HTTP/2 Activé</span>
            <span class="badge">✓ HSTS Activé</span>
            <span class="badge">✓ Redirection HTTP → HTTPS</span>
        </div>

        <div class="footer">
            <p><strong>TP4 Sécurité Web</strong></p>
            <p>Configuration NGINX avec certificat SSL/TLS</p>
        </div>
    </div>

    <script>
        // Afficher le domaine actuel
        document.getElementById('domain').textContent = window.location.hostname;
        
        // Vérifier le protocole
        if (window.location.protocol !== 'https:') {
            document.body.innerHTML = '<div style="padding:50px;text-align:center;"><h1>⚠️ Attention</h1><p>Cette page doit être accédée via HTTPS</p></div>';
        }
    </script>
</body>
</html>
EOF

sudo chown www-data:www-data "${WEB_ROOT}/${DOMAIN}.html"
sudo chmod 644 "${WEB_ROOT}/${DOMAIN}.html"
print_success "Page web créée : ${WEB_ROOT}/${DOMAIN}.html"

# =============================================================================
# ÉTAPE 7 : Configuration NGINX
# =============================================================================
print_step "7/10" "Configuration de NGINX avec HTTPS..."

sudo tee "${NGINX_AVAILABLE}/${DOMAIN}" > /dev/null <<EOF
# =============================================================================
# Configuration HTTPS pour ${DOMAIN}
# Générée automatiquement - TP4 Sécurité Web
# =============================================================================

# Redirection HTTP → HTTPS (force l'utilisation de HTTPS)
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} ${WWW};
    
    # Redirection permanente vers HTTPS
    return 301 https://\$server_name\$request_uri;
}

# Serveur HTTPS principal
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN} ${WWW};

    # =========================================================================
    # Configuration SSL/TLS
    # =========================================================================
    
    # Certificats
    ssl_certificate     ${CERT_DIR}/${DOMAIN}.crt;
    ssl_certificate_key ${KEY_DIR}/${DOMAIN}.key;

    # Protocoles SSL/TLS (désactive les versions obsolètes)
    ssl_protocols TLSv1.2 TLSv1.3;
    
    # Suites de chiffrement sécurisées (ordre de préférence)
    ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers on;
    
    # Optimisation des sessions SSL
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    
    # Paramètres Diffie-Hellman
    ssl_dhparam /etc/nginx/dhparam.pem;

    # =========================================================================
    # En-têtes de sécurité
    # =========================================================================
    
    # HSTS : Force l'utilisation de HTTPS pendant 1 an
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    
    # Protection contre le clickjacking
    add_header X-Frame-Options "DENY" always;
    
    # Empêche le navigateur de deviner le type MIME
    add_header X-Content-Type-Options "nosniff" always;
    
    # Protection XSS pour les anciens navigateurs
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Politique de référent
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Content Security Policy (basique)
    add_header Content-Security-Policy "default-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:;" always;

    # =========================================================================
    # Configuration du site web
    # =========================================================================
    
    root ${WEB_ROOT};
    index ${DOMAIN}.html index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # Gestion des erreurs
    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;

    # Logs
    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log /var/log/nginx/${DOMAIN}_error.log warn;

    # Désactiver les logs pour les fichiers statiques
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        access_log off;
    }
}
EOF

print_success "Configuration NGINX créée"

# =============================================================================
# ÉTAPE 8 : Activation du site
# =============================================================================
print_step "8/10" "Activation du site et désactivation du site par défaut..."

# Créer le lien symbolique
sudo ln -sf "${NGINX_AVAILABLE}/${DOMAIN}" "${NGINX_ENABLED}/${DOMAIN}"
print_success "Site activé"

# Désactiver le site par défaut
if [[ -f "${NGINX_ENABLED}/default" ]]; then
    sudo rm -f "${NGINX_ENABLED}/default"
    print_success "Site par défaut désactivé"
fi

# =============================================================================
# ÉTAPE 9 : Test et redémarrage de NGINX
# =============================================================================
print_step "9/10" "Test de la configuration NGINX..."

echo "--- Sortie de nginx -t ---"
if sudo nginx -t; then
    print_success "Configuration NGINX valide"
else
    print_error "Erreur dans la configuration NGINX"
    exit 1
fi
echo "-------------------------"

print_step "9.5/10" "Redémarrage de NGINX..."
echo "--- Redémarrage en cours ---"
sudo systemctl restart nginx
sudo systemctl status nginx --no-pager -l
echo "-----------------------------"

if sudo systemctl is-active --quiet nginx; then
    print_success "NGINX redémarré avec succès"
else
    print_error "NGINX n'a pas démarré correctement"
    exit 1
fi

# =============================================================================
# ÉTAPE 10 : Configuration du pare-feu
# =============================================================================
print_step "10/10" "Configuration du pare-feu (ufw)..."

if command -v ufw &> /dev/null; then
    echo "Autorisation des ports 80 et 443..."
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp || true
    print_success "Ports 80 et 443 ouverts"
else
    print_warning "ufw non installé (pare-feu non configuré)"
fi

# =============================================================================
# TESTS FINAUX
# =============================================================================
echo ""
echo "=========================================================="
echo "  🎉 CONFIGURATION TERMINÉE AVEC SUCCÈS !"
echo "=========================================================="
echo ""

# Test de connectivité HTTPS
print_step "TEST" "Vérification de la connexion HTTPS..."
sleep 2

echo "--- Test curl ---"
curl -I "https://${DOMAIN}" 2>&1 || print_warning "Le serveur ne répond pas encore"
echo "-----------------"

if curl -k -I "https://${DOMAIN}" 2>/dev/null | grep -q "200 OK"; then
    print_success "Le serveur HTTPS répond correctement"
else
    print_warning "Le serveur ne répond pas encore (attends quelques secondes)"
fi

# Affichage des informations finales
echo ""
echo "📋 INFORMATIONS IMPORTANTES :"
echo ""
echo "   🌐 URLs à tester dans ton navigateur :"
echo "      • https://${DOMAIN}"
echo "      • https://${WWW}"
echo "      • http://${DOMAIN} (redirige vers HTTPS)"
echo ""
echo "   🔒 Certificat SSL :"
echo "      • Type : mkcert (trusted par ton système)"
echo "      • Emplacement : ${CERT_DIR}/${DOMAIN}.crt"
echo "      • Tu devrais voir un cadenas vert 🔒"
echo ""
echo "   ⚠️  IMPORTANT :"
echo "      • Redémarre TOUS tes navigateurs (Chrome, Firefox, etc.)"
echo "      • Si le cadenas est rouge : efface le cache du navigateur"
echo ""
echo "   📝 Fichiers de configuration :"
echo "      • NGINX : ${NGINX_AVAILABLE}/${DOMAIN}"
echo "      • Page web : ${WEB_ROOT}/${DOMAIN}.html"
echo "      • Logs : /var/log/nginx/${DOMAIN}_*.log"
echo ""
echo "   🔧 Commandes utiles :"
echo "      • Voir les logs : sudo tail -f /var/log/nginx/${DOMAIN}_error.log"
echo "      • Redémarrer NGINX : sudo systemctl restart nginx"
echo "      • Tester la config : sudo nginx -t"
echo "      • Voir le certificat : openssl x509 -in ${CERT_DIR}/${DOMAIN}.crt -text -noout"
echo ""
echo "=========================================================="
echo ""

# Test final avec curl
echo "🧪 Test final détaillé avec curl :"
echo "======================================"
curl -Ivs "https://${DOMAIN}" 2>&1 | head -n 20 || print_warning "Erreur curl (normal si le serveur démarre)"
echo "======================================"

echo ""
echo "✅ Script terminé ! Ouvre ton navigateur et teste le site."
echo ""
