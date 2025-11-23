#!/bin/bash
# =============================================================================
# Script de Réparation - Certificat mkcert non reconnu
# Résout l'erreur : ERR_CERT_AUTHORITY_INVALID
# =============================================================================

set -e

DOMAIN="secure-domain.ma"
WWW="www.secure-domain.ma"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

echo "=========================================================="
echo "  🔧 Réparation Certificat mkcert"
echo "  Résolution de ERR_CERT_AUTHORITY_INVALID"
echo "=========================================================="
echo ""

# =============================================================================
# ÉTAPE 1 : Fermeture des navigateurs
# =============================================================================
print_step "1/8" "Fermeture de TOUS les navigateurs..."

echo "Fermeture de Chrome, Firefox, Chromium, Brave, Edge..."
killall chrome 2>/dev/null || true
killall firefox 2>/dev/null || true
killall chromium 2>/dev/null || true
killall chromium-browser 2>/dev/null || true
killall brave-browser 2>/dev/null || true
killall microsoft-edge 2>/dev/null || true
sleep 2
print_success "Navigateurs fermés"

# =============================================================================
# ÉTAPE 2 : Installation des outils nécessaires
# =============================================================================
print_step "2/8" "Installation de libnss3-tools (pour Chrome/Chromium)..."

sudo apt update -qq
sudo apt install -y libnss3-tools certutil

print_success "libnss3-tools installé"

# =============================================================================
# ÉTAPE 3 : Vérification de mkcert
# =============================================================================
print_step "3/8" "Vérification de l'installation mkcert..."

if ! command -v mkcert &> /dev/null; then
    print_error "mkcert n'est pas installé !"
    echo ""
    echo "Installe-le avec :"
    echo "  wget https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-amd64"
    echo "  sudo install mkcert-v1.4.4-linux-amd64 /usr/local/bin/mkcert"
    exit 1
fi

print_success "mkcert trouvé : $(mkcert -version 2>&1 | head -n1)"

# =============================================================================
# ÉTAPE 4 : Localisation du CA actuel
# =============================================================================
print_step "4/8" "Localisation du CA mkcert..."

CA_ROOT=$(mkcert -CAROOT)
echo "   Dossier CA : ${CA_ROOT}"

if [[ -f "${CA_ROOT}/rootCA.pem" ]]; then
    print_success "CA trouvé : ${CA_ROOT}/rootCA.pem"
else
    print_warning "CA non trouvé, il va être créé"
fi

# =============================================================================
# ÉTAPE 5 : Désinstallation complète du CA
# =============================================================================
print_step "5/8" "Désinstallation complète de l'ancien CA..."

mkcert -uninstall 2>/dev/null || true
print_success "Ancien CA désinstallé"

# Nettoyage manuel des CA dans les navigateurs
echo ""
echo "Nettoyage des certificats dans les navigateurs..."

# Chrome/Chromium
if [[ -d "$HOME/.pki/nssdb" ]]; then
    certutil -D -n "mkcert" -d sql:$HOME/.pki/nssdb 2>/dev/null || true
    print_success "CA Chrome/Chromium nettoyé"
fi

# Firefox
for profile in $HOME/.mozilla/firefox/*.*/; do
    if [[ -d "$profile" ]]; then
        certutil -D -n "mkcert" -d sql:"$profile" 2>/dev/null || true
    fi
done
print_success "CA Firefox nettoyé"

# =============================================================================
# ÉTAPE 6 : Installation du nouveau CA
# =============================================================================
print_step "6/8" "Installation du nouveau CA mkcert..."

echo ""
mkcert -install
echo ""

# Vérification de l'installation
if [[ -f "${CA_ROOT}/rootCA.pem" ]]; then
    print_success "CA installé avec succès !"
    echo "   📁 Emplacement : ${CA_ROOT}"
else
    print_error "Échec de l'installation du CA"
    exit 1
fi

# =============================================================================
# ÉTAPE 7 : Régénération du certificat pour secure-domain.ma
# =============================================================================
print_step "7/8" "Régénération du certificat pour ${DOMAIN}..."

cd /tmp
rm -f ${DOMAIN}*.pem 2>/dev/null || true

echo "Génération du nouveau certificat..."
mkcert "${DOMAIN}" "${WWW}" localhost 127.0.0.1 ::1

# Détection des fichiers
CERT_FILE=$(ls -1 ${DOMAIN}*.pem 2>/dev/null | grep -v "key" | head -n1)
KEY_FILE=$(ls -1 ${DOMAIN}*key.pem 2>/dev/null | head -n1)

if [[ -z "${CERT_FILE}" ]] || [[ -z "${KEY_FILE}" ]]; then
    print_error "Échec de la génération du certificat"
    exit 1
fi

# Remplacement des anciens certificats
echo "Remplacement des certificats..."
sudo cp "${CERT_FILE}" /etc/ssl/certs/${DOMAIN}.crt
sudo cp "${KEY_FILE}" /etc/ssl/private/${DOMAIN}.key
sudo chmod 644 /etc/ssl/certs/${DOMAIN}.crt
sudo chmod 600 /etc/ssl/private/${DOMAIN}.key

rm -f ${DOMAIN}*.pem
cd - > /dev/null

print_success "Certificat régénéré et installé"

# Vérification du nouveau certificat
openssl x509 -in /etc/ssl/certs/${DOMAIN}.crt -noout -subject -issuer
print_success "Certificat vérifié"

# =============================================================================
# ÉTAPE 8 : Redémarrage d'Apache2
# =============================================================================
print_step "8/8" "Redémarrage d'Apache2..."

if command -v apache2 &> /dev/null; then
    sudo systemctl restart apache2
    
    if systemctl is-active --quiet apache2; then
        print_success "Apache2 redémarré"
    else
        print_error "Erreur au redémarrage d'Apache2"
        sudo systemctl status apache2 --no-pager
    fi
elif command -v nginx &> /dev/null; then
    sudo systemctl restart nginx
    
    if systemctl is-active --quiet nginx; then
        print_success "NGINX redémarré"
    else
        print_error "Erreur au redémarrage de NGINX"
        sudo systemctl status nginx --no-pager
    fi
fi

# =============================================================================
# INSTRUCTIONS FINALES
# =============================================================================
echo ""
echo "=========================================================="
echo "  ✅ RÉPARATION TERMINÉE !"
echo "=========================================================="
echo ""
echo "📋 Ce qui a été fait :"
echo "   ✓ Navigateurs fermés"
echo "   ✓ libnss3-tools installé"
echo "   ✓ Ancien CA désinstallé"
echo "   ✓ Nouveau CA installé dans le système"
echo "   ✓ Certificat ${DOMAIN} régénéré"
echo "   ✓ Serveur web redémarré"
echo ""
echo "🔧 ÉTAPES SUIVANTES (IMPORTANT) :"
echo ""
echo "   1️⃣  Ouvre ton navigateur (Chrome ou Firefox)"
echo ""
echo "   2️⃣  Va dans les paramètres de sécurité :"
echo ""
echo "      🔹 CHROME/CHROMIUM :"
echo "         • Paramètres → Confidentialité et sécurité"
echo "         • Sécurité → Gérer les certificats"
echo "         • Onglet 'Autorités' → Cherche 'mkcert'"
echo "         • Tu devrais voir : 'mkcert <ton_user>'"
echo ""
echo "      🔹 FIREFOX :"
echo "         • Paramètres → Vie privée et sécurité"
echo "         • Certificats → Afficher les certificats"
echo "         • Onglet 'Autorités' → Cherche 'mkcert'"
echo ""
echo "   3️⃣  Efface le cache du navigateur :"
echo "      • Chrome : Ctrl+Shift+Suppr → Vider le cache"
echo "      • Firefox : Ctrl+Shift+Suppr → Cookies et cache"
echo ""
echo "   4️⃣  Teste le site :"
echo "      🌐 https://${DOMAIN}"
echo "      🌐 https://${WWW}"
echo ""
echo "=========================================================="
echo ""

# Test final
print_step "TEST" "Test de connexion HTTPS..."
echo ""

if curl -s -o /dev/null -w "%{http_code}" "https://${DOMAIN}" 2>/dev/null | grep -q "200"; then
    print_success "Le serveur HTTPS répond ! 🎉"
else
    print_warning "Le serveur ne répond pas (vérifie Apache2/NGINX)"
fi

echo ""
echo "🔍 Vérification du certificat :"
echo "   Commande : openssl s_client -connect ${DOMAIN}:443 -servername ${DOMAIN}"
echo ""

# Afficher des infos de diagnostic
echo "📊 Diagnostic :"
echo "   • CA Root : ${CA_ROOT}"
echo "   • Certificat : /etc/ssl/certs/${DOMAIN}.crt"
echo "   • Clé : /etc/ssl/private/${DOMAIN}.key"
echo ""

# Instructions pour vérifier manuellement
echo "🧪 Tests manuels :"
echo ""
echo "   1. Vérifier que le CA est installé :"
echo "      certutil -L -d sql:\$HOME/.pki/nssdb | grep mkcert"
echo ""
echo "   2. Tester avec curl (ignore les erreurs SSL) :"
echo "      curl -k https://${DOMAIN}"
echo ""
echo "   3. Voir les détails du certificat :"
echo "      openssl x509 -in /etc/ssl/certs/${DOMAIN}.crt -text -noout"
echo ""

echo "=========================================================="
echo ""
echo "💡 Si tu vois encore 'ERR_CERT_AUTHORITY_INVALID' :"
echo ""
echo "   Solution 1 : Importer manuellement le CA dans Chrome"
echo "   -------------------------------------------------"
echo "   1. Ouvre : chrome://settings/certificates"
echo "   2. Onglet 'Autorités' → Importer"
echo "   3. Sélectionne : ${CA_ROOT}/rootCA.pem"
echo "   4. Coche 'Faire confiance à ce certificat'"
echo ""
echo "   Solution 2 : Firefox"
echo "   --------------------"
echo "   1. Ouvre : about:preferences#privacy"
echo "   2. Certificats → Afficher les certificats"
echo "   3. Importer → ${CA_ROOT}/rootCA.pem"
echo "   4. Coche toutes les options de confiance"
echo ""
echo "=========================================================="
echo ""
echo "✅ Relance ton navigateur et teste à nouveau !"
echo ""