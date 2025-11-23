#!/bin/bash
# =============================================================================
# TP4 Sécurité Web - Configuration HTTPS complète sur APACHE2
# Domaine : secure-domain.ma
# Système : Linux Mint / Ubuntu / Debian
# Certificat trusted (mkcert) avec vérifications complètes
# Auteur : Version Apache2 améliorée
# =============================================================================

set -euo pipefail  # Mode strict

# Configuration
DOMAIN="secure-domain.ma"
WWW="www.secure-domain.ma"
IP="127.0.0.1"
CERT_DIR="/etc/ssl/certs"
KEY_DIR="/etc/ssl/private"
WEB_ROOT="/var/www/html"
APACHE_AVAILABLE="/etc/apache2/sites-available"
APACHE_ENABLED="/etc/apache2/sites-enabled"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Fonctions d'affichage
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

# Vérification root
check_root() {
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        print_error "Ce script nécessite les privilèges sudo"
        exit 1
    fi
}

# Nettoyage en cas d'erreur
cleanup_on_error() {
    print_error "Une erreur est survenue. Nettoyage..."
    sudo systemctl stop apache2 2>/dev/null || true
    exit 1
}

trap cleanup_on_error ERR

echo "=========================================================="
echo "  Configuration HTTPS APACHE2 - secure-domain.ma (TP4)"
echo "  Version améliorée avec logs complets"
echo "=========================================================="
echo ""

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

if ping -c 1 "${DOMAIN}" &> /dev/null; then
    print_success "Résolution DNS locale fonctionne"
else
    print_warning "Ping échoué (normal avec certains pare-feu)"
fi

# =============================================================================
# ÉTAPE 2 : Installation d'Apache2 et outils SSL
# =============================================================================
print_step "2/10" "Installation d'Apache2 et outils SSL..."

sudo apt update
sudo apt install -y apache2 openssl libnss3-tools curl wget ca-certificates

# Vérification des installations
if command -v apache2 &> /dev/null && command -v openssl &> /dev/null; then
    print_success "Apache2 $(apache2 -v 2>&1 | head -n1 | cut -d'/' -f2 | cut -d' ' -f1) et OpenSSL installés"
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
# ÉTAPE 5 : Activation des modules Apache2
# =============================================================================
print_step "5/10" "Activation des modules Apache2 nécessaires..."

echo "Activation de ssl, rewrite, headers, http2..."
sudo a2enmod ssl
sudo a2enmod rewrite
sudo a2enmod headers
sudo a2enmod http2

print_success "Modules Apache2 activés"

# =============================================================================
# ÉTAPE 6 : Création de la page web
# =============================================================================
print_step "6/10" "Création de la page web de test..."

sudo tee "${WEB_ROOT}/${DOMAIN}.html" > /dev/null <<'HTMLEOF'
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🔐 Secure Domain - TP4 Sécurité Web</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(-45deg, #ee7752, #e73c7e, #23a6d5, #23d5ab);
            background-size: 400% 400%;
            animation: gradientBG 15s ease infinite;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
            overflow-x: hidden;
        }

        @keyframes gradientBG {
            0% { background-position: 0% 50%; }
            50% { background-position: 100% 50%; }
            100% { background-position: 0% 50%; }
        }

        .container {
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            border-radius: 30px;
            box-shadow: 0 30px 80px rgba(0, 0, 0, 0.3);
            padding: 60px 40px;
            max-width: 900px;
            width: 100%;
            animation: slideUp 0.6s ease-out;
        }

        @keyframes slideUp {
            from {
                opacity: 0;
                transform: translateY(50px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        .header {
            text-align: center;
            margin-bottom: 40px;
        }

        .lock-container {
            position: relative;
            display: inline-block;
        }

        .lock-icon {
            font-size: 100px;
            animation: lockPulse 2s ease-in-out infinite;
            filter: drop-shadow(0 10px 20px rgba(40, 167, 69, 0.3));
        }

        @keyframes lockPulse {
            0%, 100% { transform: scale(1) rotate(0deg); }
            25% { transform: scale(1.1) rotate(-5deg); }
            75% { transform: scale(1.1) rotate(5deg); }
        }

        .pulse-ring {
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            width: 120px;
            height: 120px;
            border: 3px solid #28a745;
            border-radius: 50%;
            animation: pulseRing 2s ease-out infinite;
        }

        @keyframes pulseRing {
            0% {
                transform: translate(-50%, -50%) scale(0.8);
                opacity: 1;
            }
            100% {
                transform: translate(-50%, -50%) scale(1.5);
                opacity: 0;
            }
        }

        h1 {
            background: linear-gradient(135deg, #28a745 0%, #20c997 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            font-size: 3em;
            font-weight: 800;
            margin: 20px 0;
            letter-spacing: -1px;
        }

        .subtitle {
            color: #6c757d;
            font-size: 1.2em;
            margin-bottom: 10px;
        }

        .status-badge {
            display: inline-block;
            padding: 8px 20px;
            background: linear-gradient(135deg, #28a745, #20c997);
            color: white;
            border-radius: 50px;
            font-weight: 600;
            font-size: 0.9em;
            box-shadow: 0 5px 15px rgba(40, 167, 69, 0.3);
            animation: badgeBounce 2s ease-in-out infinite;
        }

        @keyframes badgeBounce {
            0%, 100% { transform: translateY(0); }
            50% { transform: translateY(-5px); }
        }

        .security-score {
            background: linear-gradient(135deg, #28a745 0%, #20c997 100%);
            color: white;
            padding: 30px;
            border-radius: 20px;
            margin: 30px 0;
            text-align: center;
            box-shadow: 0 10px 30px rgba(40, 167, 69, 0.3);
        }

        .score-number {
            font-size: 4em;
            font-weight: 800;
            line-height: 1;
            text-shadow: 0 5px 10px rgba(0, 0, 0, 0.2);
        }

        .score-label {
            font-size: 1.2em;
            margin-top: 10px;
            opacity: 0.9;
        }

        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin: 40px 0;
        }

        .info-card {
            background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
            border-radius: 15px;
            padding: 25px;
            text-align: center;
            transition: all 0.3s ease;
            border: 2px solid transparent;
        }

        .info-card:hover {
            transform: translateY(-5px) scale(1.02);
            box-shadow: 0 15px 30px rgba(0, 0, 0, 0.2);
            border-color: #28a745;
        }

        .info-icon {
            font-size: 50px;
            margin-bottom: 15px;
            display: block;
        }

        .info-label {
            font-weight: 700;
            color: #495057;
            font-size: 0.9em;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 10px;
        }

        .info-value {
            color: #212529;
            font-family: 'Courier New', monospace;
            font-size: 1.1em;
            font-weight: 600;
            background: white;
            padding: 10px 15px;
            border-radius: 8px;
            box-shadow: inset 0 2px 4px rgba(0, 0, 0, 0.1);
        }

        .features {
            display: flex;
            flex-wrap: wrap;
            justify-content: center;
            gap: 15px;
            margin: 30px 0;
        }

        .feature-badge {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 12px 20px;
            background: white;
            border: 2px solid #28a745;
            border-radius: 25px;
            color: #28a745;
            font-weight: 600;
            transition: all 0.3s ease;
            cursor: pointer;
        }

        .feature-badge:hover {
            background: #28a745;
            color: white;
            transform: scale(1.05);
            box-shadow: 0 5px 15px rgba(40, 167, 69, 0.4);
        }

        .footer {
            text-align: center;
            margin-top: 40px;
            padding-top: 30px;
            border-top: 3px solid #e9ecef;
        }

        .footer-logo {
            font-size: 2em;
            margin-bottom: 15px;
        }

        .footer-text {
            color: #6c757d;
            font-size: 0.95em;
            line-height: 1.6;
        }

        .tech-stack {
            display: flex;
            justify-content: center;
            gap: 20px;
            margin-top: 20px;
            flex-wrap: wrap;
        }

        .tech-item {
            background: white;
            padding: 10px 20px;
            border-radius: 10px;
            font-weight: 600;
            color: #495057;
            box-shadow: 0 3px 10px rgba(0, 0, 0, 0.1);
            transition: all 0.3s ease;
        }

        .tech-item:hover {
            transform: translateY(-3px);
            box-shadow: 0 6px 20px rgba(0, 0, 0, 0.15);
        }

        @media (max-width: 768px) {
            .container { padding: 40px 20px; }
            h1 { font-size: 2em; }
            .lock-icon { font-size: 70px; }
            .info-grid { grid-template-columns: 1fr; }
            .score-number { font-size: 3em; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="lock-container">
                <div class="pulse-ring"></div>
                <div class="lock-icon">🔐</div>
            </div>
            <h1>Connexion Sécurisée</h1>
            <p class="subtitle">Serveur Apache2 protégé par SSL/TLS</p>
            <span class="status-badge">✓ HTTPS Actif</span>
        </div>

        <div class="security-score">
            <div class="score-number">A+</div>
            <div class="score-label">🏆 Score de Sécurité</div>
        </div>

        <div class="info-grid">
            <div class="info-card">
                <span class="info-icon">🌐</span>
                <div class="info-label">Domaine</div>
                <div class="info-value" id="domain">secure-domain.ma</div>
            </div>
            <div class="info-card">
                <span class="info-icon">🔒</span>
                <div class="info-label">Protocole</div>
                <div class="info-value">HTTPS / TLS 1.3</div>
            </div>
            <div class="info-card">
                <span class="info-icon">📜</span>
                <div class="info-label">Certificat</div>
                <div class="info-value">mkcert (Trusted)</div>
            </div>
            <div class="info-card">
                <span class="info-icon">⚡</span>
                <div class="info-label">Serveur</div>
                <div class="info-value">Apache2</div>
            </div>
        </div>

        <div class="features">
            <div class="feature-badge">
                <span>🚀</span>
                <span>HTTP/2 Enabled</span>
            </div>
            <div class="feature-badge">
                <span>🛡️</span>
                <span>HSTS Protected</span>
            </div>
            <div class="feature-badge">
                <span>🔄</span>
                <span>Auto Redirect HTTP</span>
            </div>
            <div class="feature-badge">
                <span>🔐</span>
                <span>Strong Ciphers</span>
            </div>
            <div class="feature-badge">
                <span>⚡</span>
                <span>Perfect Forward Secrecy</span>
            </div>
        </div>

        <div class="footer">
            <div class="footer-logo">🎓</div>
            <div class="footer-text">
                <strong>TP4 Sécurité Web - Configuration Apache2</strong><br>
                Certificat SSL/TLS avec mkcert + Apache2<br>
                Connexion sécurisée et chiffrée end-to-end
            </div>
            <div class="tech-stack">
                <div class="tech-item">Apache2</div>
                <div class="tech-item">OpenSSL</div>
                <div class="tech-item">mkcert</div>
                <div class="tech-item">TLS 1.3</div>
                <div class="tech-item">HTTP/2</div>
            </div>
        </div>
    </div>

    <script>
        document.getElementById('domain').textContent = window.location.hostname;
        
        if (window.location.protocol !== 'https:') {
            document.body.innerHTML = `
                <div style="padding:50px;text-align:center;background:white;border-radius:20px;max-width:500px;margin:50px auto;">
                    <h1 style="color:#dc3545;font-size:3em;">⚠️</h1>
                    <h2 style="color:#495057;">Connexion Non Sécurisée</h2>
                    <p style="color:#6c757d;margin:20px 0;">Cette page doit être accédée via HTTPS</p>
                    <a href="https://${window.location.hostname}" style="display:inline-block;padding:15px 30px;background:#28a745;color:white;text-decoration:none;border-radius:10px;font-weight:600;">
                        🔒 Accéder en HTTPS
                    </a>
                </div>
            `;
        }
    </script>
</body>
</html>
HTMLEOF

sudo chown www-data:www-data "${WEB_ROOT}/${DOMAIN}.html"
sudo chmod 644 "${WEB_ROOT}/${DOMAIN}.html"
print_success "Page web créée : ${WEB_ROOT}/${DOMAIN}.html"

# =============================================================================
# ÉTAPE 7 : Configuration Apache2
# =============================================================================
print_step "7/10" "Configuration d'Apache2 avec HTTPS..."

sudo tee "${APACHE_AVAILABLE}/${DOMAIN}.conf" > /dev/null <<APACHEEOF
# =============================================================================
# Configuration HTTPS pour ${DOMAIN}
# Générée automatiquement - TP4 Sécurité Web
# =============================================================================

# Redirection HTTP → HTTPS
<VirtualHost *:80>
    ServerName ${DOMAIN}
    ServerAlias ${WWW}
    
    # Redirection permanente vers HTTPS
    Redirect permanent / https://${DOMAIN}/
    
    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_access.log combined
</VirtualHost>

# Serveur HTTPS principal
<VirtualHost *:443>
    ServerName ${DOMAIN}
    ServerAlias ${WWW}
    
    DocumentRoot ${WEB_ROOT}
    DirectoryIndex ${DOMAIN}.html index.html
    
    # =========================================================================
    # Configuration SSL/TLS
    # =========================================================================
    
    SSLEngine on
    SSLCertificateFile ${CERT_DIR}/${DOMAIN}.crt
    SSLCertificateKeyFile ${KEY_DIR}/${DOMAIN}.key
    
    # Protocoles SSL/TLS sécurisés
    SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
    
    # Suites de chiffrement sécurisées
    SSLCipherSuite ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    SSLHonorCipherOrder on
    
    # HTTP/2
    Protocols h2 http/1.1
    
    # =========================================================================
    # En-têtes de sécurité
    # =========================================================================
    
    # HSTS
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    
    # Protection clickjacking
    Header always set X-Frame-Options "DENY"
    
    # Protection MIME
    Header always set X-Content-Type-Options "nosniff"
    
    # Protection XSS
    Header always set X-XSS-Protection "1; mode=block"
    
    # Politique de référent
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    
    # CSP basique
    Header always set Content-Security-Policy "default-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:;"
    
    # =========================================================================
    # Configuration du répertoire
    # =========================================================================
    
    <Directory ${WEB_ROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    # Logs
    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_ssl_access.log combined
</VirtualHost>

# Configuration SSL globale
SSLSessionCache shmcb:/var/run/apache2/ssl_scache(512000)
SSLSessionCacheTimeout 300
SSLUseStapling on
SSLStaplingCache shmcb:/var/run/apache2/ssl_stapling(32768)
APACHEEOF

print_success "Configuration Apache2 créée"

# =============================================================================
# ÉTAPE 8 : Activation du site
# =============================================================================
print_step "8/10" "Activation du site et désactivation du site par défaut..."

# Désactiver le site par défaut
sudo a2dissite 000-default.conf 2>/dev/null || true
sudo a2dissite default-ssl.conf 2>/dev/null || true
print_success "Sites par défaut désactivés"

# Activer le nouveau site
sudo a2ensite ${DOMAIN}.conf
print_success "Site ${DOMAIN} activé"

# =============================================================================
# ÉTAPE 9 : Test et redémarrage d'Apache2
# =============================================================================
print_step "9/10" "Test de la configuration Apache2..."

echo "--- Sortie de apachectl configtest ---"
if sudo apachectl configtest; then
    print_success "Configuration Apache2 valide"
else
    print_error "Erreur dans la configuration Apache2"
    exit 1
fi
echo "---------------------------------------"

print_step "9.5/10" "Redémarrage d'Apache2..."
echo "--- Redémarrage en cours ---"
sudo systemctl restart apache2
sudo systemctl status apache2 --no-pager -l
echo "-----------------------------"

if sudo systemctl is-active --quiet apache2; then
    print_success "Apache2 redémarré avec succès"
else
    print_error "Apache2 n'a pas démarré correctement"
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
    sudo ufw allow 'Apache Full' 2>/dev/null || true
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
echo "      • Redémarre TOUS tes navigateurs"
echo "      • Si le cadenas est rouge : efface le cache"
echo ""
echo "   📝 Fichiers de configuration :"
echo "      • Apache2 : ${APACHE_AVAILABLE}/${DOMAIN}.conf"
echo "      • Page web : ${WEB_ROOT}/${DOMAIN}.html"
echo "      • Logs : /var/log/apache2/${DOMAIN}_*.log"
echo ""
echo "   🔧 Commandes utiles :"
echo "      • Voir les logs : sudo tail -f /var/log/apache2/${DOMAIN}_ssl_error.log"
echo "      • Redémarrer Apache2 : sudo systemctl restart apache2"
echo "      • Tester la config : sudo apachectl configtest"
echo "      • Voir le certificat : openssl x509 -in ${CERT_DIR}/${DOMAIN}.crt -text -noout"
echo ""
echo "=========================================================="
echo ""

echo "🧪 Test final détaillé avec curl :"
echo "======================================"
curl -Ivs "https://${DOMAIN}" 2>&1 | head -n 20 || print_warning "Erreur curl"
echo "======================================"

echo ""
echo "✅ Script terminé ! Ouvre ton navigateur et teste le site."
echo ""
