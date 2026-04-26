#!/usr/bin/env bash
# ============================================================
# uninstall.sh — Désinstallation du plasmoid Polestar
# ============================================================

RED="\033[31m"
GREEN="\033[32m"
BOLD="\033[1m"
RESET="\033[0m"

echo -e "${BOLD}Désinstallation de Polestar Hub...${RESET}"

# 1. Arrêter et supprimer le service systemd
echo "→ Arrêt du service systemd..."
systemctl --user stop polestar-plasmoid.service 2>/dev/null
systemctl --user disable polestar-plasmoid.service 2>/dev/null
rm -f "$HOME/.config/systemd/user/polestar-plasmoid.service"
systemctl --user daemon-reload

# 2. Supprimer les fichiers du daemon et l'environnement virtuel
echo "→ Suppression des fichiers du daemon..."
rm -rf "$HOME/.local/share/polestar-plasmoid"

# 3. Supprimer le plasmoid
echo "→ Suppression du widget KDE..."
if command -v kpackagetool6 &>/dev/null; then
    kpackagetool6 --type Plasma/Applet --remove com.polestar.plasmoid 2>/dev/null
elif command -v kpackagetool5 &>/dev/null; then
    kpackagetool5 --type Plasma/Applet --remove com.polestar.plasmoid 2>/dev/null
fi
rm -rf "$HOME/.local/share/plasma/plasmoids/com.polestar.plasmoid"

echo -e "\n${GREEN}${BOLD}✅ Désinstallation terminée.${RESET}"
echo -e "Note: Vos identifiants dans ~/.config/polestar-plasmoid ont été conservés."
