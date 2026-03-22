#!/usr/bin/env bash
# uninstall.sh — Désinstallation complète du plasmoid Polestar
set -e

echo "🗑️  Désinstallation du plasmoid Polestar…"

# Arrêter et désactiver le service
systemctl --user stop    polestar-plasmoid.service 2>/dev/null || true
systemctl --user disable polestar-plasmoid.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/polestar-plasmoid.service"
systemctl --user daemon-reload

# Supprimer les fichiers
rm -rf "$HOME/.local/share/plasma/plasmoids/com.polestar.plasmoid"
rm -rf "$HOME/.local/share/polestar-plasmoid"

echo "Supprimer aussi la configuration (identifiants) ? [o/N]"
read CONFIRM
if [[ "$CONFIRM" =~ ^[Oo]$ ]]; then
    rm -rf "$HOME/.config/polestar-plasmoid"
    echo "Configuration supprimée."
fi

echo "✅ Désinstallation terminée."
echo "Redémarrez Plasma pour que les changements prennent effet :"
echo "  kquitapp6 plasmashell && kstart plasmashell"
