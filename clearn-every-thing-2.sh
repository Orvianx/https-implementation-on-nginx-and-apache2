#!/bin/bash
# =============================================================================
# Script de Nettoyage Complet - TP4 Sécurité Web
# Supprime TOUT ce qui a été installé et configuré
# Domaine : secure-domain.ma
# =============================================================================

set -e

DOMAIN="secure-domain.ma"
WWW="www.secure-domain.ma"
IP="127.0.0.1"

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
echo "  🗑️  NETTOYAGE COMPLET - Suppression de tout"
echo "=========================================================="
echo ""
echo "⚠️  CE SCRIPT VA SUPPRIMER :"
echo "   - Configuration NGINX de ${DOMAIN}"
echo "   - Certificats SSL/TLS"
echo "   - Page web ${DOMAIN}.html"
echo "   - Paramètres Diffie-Hellman"
echo "   - Entrée dans /etc/hosts"
echo "   - mkcert et son CA local"
echo "   - NGINX (optionnel)"
echo ""
read -p "Continuer ? (o/N) : " -n 1 -r
echo
if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
    echo "Annulé."
    exit 0
fi

echo ""
echo "=========================================================="
echo "  Début du nettoyage..."
echo "=========================================================="
echo ""

# =============================================================================
# ÉTAPE 1 : Arrêt de NGINX
# =============================================================================
print_step "1/10" "Arrêt de NGINX..."

if systemctl is-active --quiet nginx; then
    sudo systemctl stop nginx
    print_success "NGINX arrêté"
else
    print_warning "NGINX n'était pas en cours d'exécution"
fi

# =============================================================================
# ÉTAPE 2 : Suppression de la configuration NGINX
# =============================================================================
print_step "2/10" "Suppression de la configuration NGINX..."

# Supprimer le lien symbolique
if [[ -L /etc/nginx/sites-enabled/${DOMAIN} ]]; then
    sudo rm -f /etc/nginx/sites-enabled/${DOMAIN}
    print_success "Lien symbolique supprimé"
fi

# Supprimer le fichier de configuration
if [[ -f /etc/nginx/sites-available/${DOMAIN} ]]; then
    sudo rm -f /etc/nginx/sites-available/${DOMAIN}
    print_success "Fichier de configuration supprimé"
fi

# Restaurer le site par défaut
if [[ -f /etc/nginx/sites-available/default ]] && [[ ! -L /etc/nginx/sites-enabled/default ]]; then
    sudo ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    print_success "Site par défaut restauré"
fi

# =============================================================================
# ÉTAPE 3 : Suppression des certificats SSL
# =============================================================================
print_step "3/10" "Suppression des certificats SSL/TLS..."

if [[ -f /etc/ssl/certs/${DOMAIN}.crt ]]; then
    sudo rm -f /etc/ssl/certs/${DOMAIN}.crt
    print_success "Certificat supprimé"
fi

if [[ -f /etc/ssl/private/${DOMAIN}.key ]]; then
    sudo rm -f /etc/ssl/private/${DOMAIN}.key
    print_success "Clé privée supprimée"
fi

# Supprimer les fichiers temporaires mkcert
rm -f /tmp/${DOMAIN}*.pem 2>/dev/null || true

# =============================================================================
# ÉTAPE 4 : Suppression du fichier Diffie-Hellman
# =============================================================================
print_step "4/10" "Suppression des paramètres Diffie-Hellman..."

if [[ -f /etc/nginx/dhparam.pem ]]; then
    sudo rm -f /etc/nginx/dhparam.pem
    print_success "dhparam.pem supprimé"
else
    print_warning "dhparam.pem non trouvé"
fi

# =============================================================================
# ÉTAPE 5 : Suppression de la page web
# =============================================================================
print_step "5/10" "Suppression de la page web..."

if [[ -f /var/www/html/${DOMAIN}.html ]]; then
    sudo rm -f /var/www/html/${DOMAIN}.html
    print_success "Page web supprimée"
else
    print_warning "Page web non trouvée"
fi

# =============================================================================
# ÉTAPE 6 : Suppression des logs
# =============================================================================
print_step "6/10" "Suppression des logs NGINX..."

if [[ -f /var/log/nginx/${DOMAIN}_access.log ]]; then
    sudo rm -f /var/log/nginx/${DOMAIN}_access.log
    print_success "Access log supprimé"
fi

if [[ -f /var/log/nginx/${DOMAIN}_error.log ]]; then
    sudo rm -f /var/log/nginx/${DOMAIN}_error.log
    print_success "Error log supprimé"
fi

# =============================================================================
# ÉTAPE 7 : Suppression de l'entrée /etc/hosts
# =============================================================================
print_step "7/10" "Suppression de l'entrée dans /etc/hosts..."

if grep -q "${DOMAIN}" /etc/hosts; then
    sudo sed -i "/${DOMAIN}/d" /etc/hosts
    print_success "Entrée /etc/hosts supprimée"
else
    print_warning "Entrée non trouvée dans /etc/hosts"
fi

# =============================================================================
# ÉTAPE 8 : Désinstallation de mkcert et son CA
# =============================================================================
print_step "8/10" "Désinstallation de mkcert..."

if command -v mkcert &> /dev/null; then
    # Désinstaller le CA local
    mkcert -uninstall 2>/dev/null || true
    print_success "CA local de mkcert désinstallé"
    
    # Supprimer mkcert
    sudo rm -f /usr/local/bin/mkcert
    print_success "mkcert supprimé"
    
    # Supprimer le dossier de mkcert
    rm -rf ~/.local/share/mkcert 2>/dev/null || true
else
    print_warning "mkcert non installé"
fi

# =============================================================================
# ÉTAPE 9 : Redémarrage de NGINX
# =============================================================================
print_step "9/10" "Test et redémarrage de NGINX..."

if sudo nginx -t 2>/dev/null; then
    sudo systemctl start nginx
    print_success "NGINX redémarré avec succès"
else
    print_warning "Erreur de configuration NGINX, non redémarré"
    print_warning "Lance 'sudo nginx -t' pour voir l'erreur"
fi

# =============================================================================
# ÉTAPE 10 : Désinstallation complète (optionnel)
# =============================================================================
print_step "10/10" "Désinstallation complète (optionnel)..."
echo ""
read -p "Veux-tu aussi désinstaller NGINX et OpenSSL ? (o/N) : " -n 1 -r
echo
if [[ $REPLY =~ ^[OoYy]$ ]]; then
    print_warning "Désinstallation de NGINX et OpenSSL..."
    sudo systemctl stop nginx 2>/dev/null || true
    sudo systemctl disable nginx 2>/dev/null || true
    sudo apt remove --purge -y nginx nginx-common nginx-core 2>/dev/null || true
    sudo apt autoremove -y 2>/dev/null || true
    print_success "NGINX complètement désinstallé"
else
    print_success "NGINX conservé (seulement la config supprimée)"
fi

# =============================================================================
# RÉSUMÉ FINAL
# =============================================================================
echo ""
echo "=========================================================="
echo "  ✅ NETTOYAGE TERMINÉ !"
echo "=========================================================="
echo ""
echo "📋 Ce qui a été supprimé :"
echo "   ✓ Configuration NGINX de ${DOMAIN}"
echo "   ✓ Certificats SSL/TLS"
echo "   ✓ Paramètres Diffie-Hellman"
echo "   ✓ Page web ${DOMAIN}.html"
echo "   ✓ Logs NGINX"
echo "   ✓ Entrée dans /etc/hosts"
echo "   ✓ mkcert et CA local"
echo ""
echo "📝 Ce qui reste (si tu as choisi de conserver) :"
echo "   • NGINX (serveur web)"
echo "   • OpenSSL (outil SSL)"
echo "   • Configuration par défaut de NGINX"
echo ""
echo "🔄 Pour réinstaller tout :"
echo "   Lance à nouveau le script d'installation"
echo ""
echo "=========================================================="
echo ""

# Vérification finale
if [[ -f /etc/nginx/sites-available/${DOMAIN} ]] || \
   [[ -f /etc/ssl/certs/${DOMAIN}.crt ]] || \
   [[ -f /var/www/html/${DOMAIN}.html ]]; then
    print_error "Attention : Certains fichiers n'ont pas été supprimés"
    echo "   Vérifie manuellement avec :"
    echo "   ls -la /etc/nginx/sites-available/"
    echo "   ls -la /etc/ssl/certs/"
    echo "   ls -la /var/www/html/"
else
    print_success "Nettoyage complet réussi !"
fi

echo
