#!/bin/bash
# =============================================================================
# Script de Nettoyage Complet - TP4 Sécurité Web (Apache2)
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
echo "  🗑️  NETTOYAGE COMPLET APACHE2 - Suppression de tout"
echo "=========================================================="
echo ""
echo "⚠️  CE SCRIPT VA SUPPRIMER :"
echo "   - Configuration Apache2 de ${DOMAIN}"
echo "   - Certificats SSL/TLS"
echo "   - Page web ${DOMAIN}.html"
echo "   - Modules Apache2 activés"
echo "   - Entrée dans /etc/hosts"
echo "   - mkcert et son CA local"
echo "   - Apache2 (optionnel)"
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
# ÉTAPE 1 : Arrêt d'Apache2
# =============================================================================
print_step "1/11" "Arrêt d'Apache2..."

if systemctl is-active --quiet apache2; then
    sudo systemctl stop apache2
    print_success "Apache2 arrêté"
else
    print_warning "Apache2 n'était pas en cours d'exécution"
fi

# =============================================================================
# ÉTAPE 2 : Désactivation du site
# =============================================================================
print_step "2/11" "Désactivation du site ${DOMAIN}..."

if [[ -L /etc/apache2/sites-enabled/${DOMAIN}.conf ]]; then
    sudo a2dissite ${DOMAIN}.conf
    print_success "Site ${DOMAIN} désactivé"
else
    print_warning "Site déjà désactivé"
fi

# =============================================================================
# ÉTAPE 3 : Suppression de la configuration Apache2
# =============================================================================
print_step "3/11" "Suppression de la configuration Apache2..."

if [[ -f /etc/apache2/sites-available/${DOMAIN}.conf ]]; then
    sudo rm -f /etc/apache2/sites-available/${DOMAIN}.conf
    print_success "Fichier de configuration supprimé"
else
    print_warning "Fichier de configuration non trouvé"
fi

# Restaurer les sites par défaut
if [[ -f /etc/apache2/sites-available/000-default.conf ]]; then
    sudo a2ensite 000-default.conf 2>/dev/null || true
    print_success "Site par défaut restauré"
fi

# =============================================================================
# ÉTAPE 4 : Suppression des certificats SSL
# =============================================================================
print_step "4/11" "Suppression des certificats SSL/TLS..."

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
print_success "Fichiers temporaires supprimés"

# =============================================================================
# ÉTAPE 5 : Suppression de la page web
# =============================================================================
print_step "5/11" "Suppression de la page web..."

if [[ -f /var/www/html/${DOMAIN}.html ]]; then
    sudo rm -f /var/www/html/${DOMAIN}.html
    print_success "Page web supprimée"
else
    print_warning "Page web non trouvée"
fi

# =============================================================================
# ÉTAPE 6 : Suppression des logs
# =============================================================================
print_step "6/11" "Suppression des logs Apache2..."

sudo rm -f /var/log/apache2/${DOMAIN}_*.log 2>/dev/null || true
print_success "Logs supprimés"

# =============================================================================
# ÉTAPE 7 : Suppression de l'entrée /etc/hosts
# =============================================================================
print_step "7/11" "Suppression de l'entrée dans /etc/hosts..."

if grep -q "${DOMAIN}" /etc/hosts; then
    sudo sed -i "/${DOMAIN}/d" /etc/hosts
    print_success "Entrée /etc/hosts supprimée"
else
    print_warning "Entrée non trouvée dans /etc/hosts"
fi

# =============================================================================
# ÉTAPE 8 : Désactivation des modules (optionnel)
# =============================================================================
print_step "8/11" "Désactivation des modules Apache2 (optionnel)..."

echo ""
read -p "Désactiver les modules SSL, HTTP/2, Headers ? (o/N) : " -n 1 -r
echo
if [[ $REPLY =~ ^[OoYy]$ ]]; then
    echo "Désactivation des modules..."
    sudo a2dismod ssl 2>/dev/null || true
    sudo a2dismod http2 2>/dev/null || true
    sudo a2dismod headers 2>/dev/null || true
    sudo a2dismod rewrite 2>/dev/null || true
    print_success "Modules désactivés"
else
    print_warning "Modules conservés"
fi

# =============================================================================
# ÉTAPE 9 : Désinstallation de mkcert et son CA
# =============================================================================
print_step "9/11" "Désinstallation de mkcert..."

if command -v mkcert &> /dev/null; then
    # Désinstaller le CA local
    echo "Désinstallation du CA local..."
    mkcert -uninstall
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
# ÉTAPE 10 : Redémarrage d'Apache2
# =============================================================================
print_step "10/11" "Test et redémarrage d'Apache2..."

if sudo apachectl configtest 2>/dev/null; then
    sudo systemctl start apache2
    if systemctl is-active --quiet apache2; then
        print_success "Apache2 redémarré avec succès"
    else
        print_warning "Apache2 n'a pas démarré"
    fi
else
    print_warning "Erreur de configuration Apache2"
    print_warning "Lance 'sudo apachectl configtest' pour voir l'erreur"
fi

# =============================================================================
# ÉTAPE 11 : Désinstallation complète (optionnel)
# =============================================================================
print_step "11/11" "Désinstallation complète (optionnel)..."
echo ""
read -p "Veux-tu aussi désinstaller Apache2 et OpenSSL ? (o/N) : " -n 1 -r
echo
if [[ $REPLY =~ ^[OoYy]$ ]]; then
    print_warning "Désinstallation d'Apache2 et OpenSSL..."
    sudo systemctl stop apache2 2>/dev/null || true
    sudo systemctl disable apache2 2>/dev/null || true
    
    echo "Suppression d'Apache2..."
    sudo apt remove --purge -y apache2 apache2-utils apache2-bin apache2-data
    
    echo "Nettoyage des dépendances..."
    sudo apt autoremove -y
    
    # Supprimer les dossiers de configuration
    sudo rm -rf /etc/apache2 2>/dev/null || true
    sudo rm -rf /var/www/html/index.html 2>/dev/null || true
    
    print_success "Apache2 complètement désinstallé"
else
    print_success "Apache2 conservé (seulement la config supprimée)"
fi

# =============================================================================
# NETTOYAGE DES RÈGLES PARE-FEU
# =============================================================================
echo ""
print_step "BONUS" "Nettoyage des règles pare-feu..."

if command -v ufw &> /dev/null; then
    read -p "Supprimer les règles Apache du pare-feu ? (o/N) : " -n 1 -r
    echo
    if [[ $REPLY =~ ^[OoYy]$ ]]; then
        sudo ufw delete allow 80/tcp 2>/dev/null || true
        sudo ufw delete allow 443/tcp 2>/dev/null || true
        sudo ufw delete allow 'Apache Full' 2>/dev/null || true
        print_success "Règles pare-feu supprimées"
    fi
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
echo "   ✓ Configuration Apache2 de ${DOMAIN}"
echo "   ✓ Certificats SSL/TLS"
echo "   ✓ Page web ${DOMAIN}.html"
echo "   ✓ Logs Apache2"
echo "   ✓ Entrée dans /etc/hosts"
echo "   ✓ mkcert et CA local"
echo ""

if [[ $REPLY =~ ^[OoYy]$ ]]; then
    echo "   ✓ Apache2 complètement désinstallé"
else
    echo "📝 Ce qui reste :"
    echo "   • Apache2 (serveur web)"
    echo "   • OpenSSL (outil SSL)"
    echo "   • Configuration par défaut d'Apache2"
fi

echo ""
echo "🔄 Pour réinstaller tout :"
echo "   Lance à nouveau le script d'installation Apache2"
echo ""
echo "=========================================================="
echo ""

# Vérification finale
if [[ -f /etc/apache2/sites-available/${DOMAIN}.conf ]] || \
   [[ -f /etc/ssl/certs/${DOMAIN}.crt ]] || \
   [[ -f /var/www/html/${DOMAIN}.html ]]; then
    print_error "Attention : Certains fichiers n'ont pas été supprimés"
    echo ""
    echo "   Vérifie manuellement avec :"
    echo "   ls -la /etc/apache2/sites-available/"
    echo "   ls -la /etc/ssl/certs/"
    echo "   ls -la /var/www/html/"
else
    print_success "Nettoyage complet réussi ! Système propre."
fi

# Afficher le statut final d'Apache2
echo ""
echo "📊 Statut final d'Apache2 :"
if command -v apache2 &> /dev/null; then
    if systemctl is-active --quiet apache2; then
        echo -e "   ${GREEN}●${NC} Apache2 est actif"
        echo "   http://localhost (site par défaut)"
    else
        echo -e "   ${RED}●${NC} Apache2 est arrêté"
    fi
else
    echo -e "   ${YELLOW}○${NC} Apache2 n'est pas installé"
fi

echo ""
echo "✅ Terminé ! Ton système est propre."
echo ""