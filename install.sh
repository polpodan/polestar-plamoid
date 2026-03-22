#!/usr/bin/env bash
# ============================================================
# install.sh — Installation du plasmoid Polestar pour KDE/Plasma 6
# ============================================================
set -e

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
RESET="\033[0m"

echo -e "${BOLD}${CYAN}"
echo "  ╔════════════════════════════════════════╗"
echo "  ║     Polestar Plasmoid — Installation   ║"
echo "  ╚════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Répertoires ──────────────────────────────────────────────────────────────
PLASMOID_SRC="$(dirname "$0")/plasmoid"
DAEMON_SRC="$(dirname "$0")/daemon"
SERVICE_SRC="$(dirname "$0")/scripts/polestar-plasmoid.service"

PLASMOID_DEST="$HOME/.local/share/plasma/plasmoids/com.polestar.plasmoid"
DAEMON_DEST="$HOME/.local/share/polestar-plasmoid"
VENV_DIR="$DAEMON_DEST/venv"
VENV_PYTHON="$VENV_DIR/bin/python3"
CONFIG_DIR="$HOME/.config/polestar-plasmoid"
SERVICE_DEST="$HOME/.config/systemd/user/polestar-plasmoid.service"

# ── 1. Vérifier les dépendances ───────────────────────────────────────────────
echo -e "\n${BOLD}[1/5] Création du venv Python et installation des dépendances…${RESET}"
echo -e "  ${CYAN}(méthode venv — compatible Arch/CachyOS/Fedora)${RESET}"

if ! command -v python3 &>/dev/null; then
    echo -e "${RED}❌ python3 requis mais introuvable.${RESET}"
    exit 1
fi
echo -e "${GREEN}  ✓ python3 $(python3 --version) trouvé${RESET}"

# Créer le dossier destination avant le venv
mkdir -p "$DAEMON_DEST"

# Créer le venv si absent ou recréer si demandé
if [ ! -f "$VENV_PYTHON" ]; then
    echo -e "  Création du venv dans ${CYAN}$VENV_DIR${RESET}…"
    python3 -m venv "$VENV_DIR"
    echo -e "${GREEN}  ✓ Venv créé${RESET}"
else
    echo -e "${GREEN}  ✓ Venv déjà existant${RESET}"
fi

# Installer/mettre à jour les dépendances dans le venv
echo -e "  Installation de pypolestar et httpx dans le venv…"
"$VENV_PYTHON" -m pip install --quiet --upgrade pip
"$VENV_PYTHON" -m pip install --quiet pypolestar httpx

# Vérification
if "$VENV_PYTHON" -c "import pypolestar, httpx" 2>/dev/null; then
    echo -e "${GREEN}  ✓ pypolestar et httpx installés avec succès${RESET}"
else
    echo -e "${RED}❌ Échec de l'installation des dépendances Python.${RESET}"
    exit 1
fi

# ── 2. Configuration ──────────────────────────────────────────────────────────
echo -e "\n${BOLD}[2/5] Configuration des identifiants Polestar…${RESET}"

mkdir -p "$CONFIG_DIR"
CONFIG_FILE="$CONFIG_DIR/config.json"

if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}  ℹ  Fichier config existant détecté.${RESET}"
    read -p "  Écraser la configuration ? [o/N] " OVERWRITE
    [[ "$OVERWRITE" =~ ^[Oo]$ ]] || echo "  → Config conservée."
fi

if [[ "$OVERWRITE" =~ ^[Oo]$ ]] || [ ! -f "$CONFIG_FILE" ]; then
    echo ""
    read -p "  Email Polestar ID: " POLESTAR_EMAIL
    read -s -p "  Mot de passe Polestar: " POLESTAR_PASS
    echo ""
    read -p "  VIN de votre Polestar (laisser vide pour auto-détection): " POLESTAR_VIN

    cat > "$CONFIG_FILE" <<EOF
{
    "username": "$POLESTAR_EMAIL",
    "password": "$POLESTAR_PASS",
    "vin": ${POLESTAR_VIN:+"\"$POLESTAR_VIN\""}${POLESTAR_VIN:-null}
}
EOF
    chmod 600 "$CONFIG_FILE"
    echo -e "${GREEN}  ✓ Configuration sauvegardée (permissions: 600)${RESET}"
fi

# ── 3. Copier le daemon ───────────────────────────────────────────────────────
echo -e "\n${BOLD}[3/5] Installation du daemon Python…${RESET}"
cp "$DAEMON_SRC/polestar_daemon.py"  "$DAEMON_DEST/"
cp "$DAEMON_SRC/polestar_climate.py" "$DAEMON_DEST/"
chmod +x "$DAEMON_DEST/polestar_daemon.py"
chmod +x "$DAEMON_DEST/polestar_climate.py"
echo -e "${GREEN}  ✓ Daemon copié dans $DAEMON_DEST${RESET}"

# ── 4. Installer le service systemd ──────────────────────────────────────────
echo -e "\n${BOLD}[4/5] Configuration du service systemd…${RESET}"
mkdir -p "$(dirname "$SERVICE_DEST")"

# Copier le service en remplaçant le chemin python par celui du venv
sed "s|%h/.local/share/polestar-plasmoid/venv/bin/python3|$VENV_PYTHON|g; \
     s|ExecStart=/usr/bin/python3|ExecStart=$VENV_PYTHON|g" \
    "$SERVICE_SRC" > "$SERVICE_DEST"

# S'assurer que la ligne ExecStart pointe bien vers le venv
# (remplace toute invocation python3 par le venv dans le service)
sed -i "s|ExecStart=.*python3 |ExecStart=$VENV_PYTHON |g" "$SERVICE_DEST"

echo -e "${GREEN}  ✓ Service configuré avec le venv: $VENV_PYTHON${RESET}"

systemctl --user daemon-reload
systemctl --user enable polestar-plasmoid.service
systemctl --user start  polestar-plasmoid.service
echo -e "${GREEN}  ✓ Service systemd activé et démarré${RESET}"

# Tester la connexion API
echo -e "\n  Test de la connexion API Polestar…"
"$VENV_PYTHON" "$DAEMON_DEST/polestar_daemon.py" once && \
    echo -e "${GREEN}  ✓ Connexion réussie ! Données récupérées.${RESET}" || \
    echo -e "${YELLOW}  ⚠  Premier test échoué — vérifiez vos identifiants. Le daemon réessaiera.${RESET}"

# ── 5. Installer le plasmoid ──────────────────────────────────────────────────
echo -e "\n${BOLD}[5/5] Installation du plasmoid KDE…${RESET}"
mkdir -p "$PLASMOID_DEST"
cp -r "$PLASMOID_SRC/." "$PLASMOID_DEST/"
echo -e "${GREEN}  ✓ Plasmoid copié dans $PLASMOID_DEST${RESET}"

# Vérifier si kpackagetool6 est dispo
if command -v kpackagetool6 &>/dev/null; then
    echo "  Rechargement du package Plasma…"
    kpackagetool6 --type Plasma/Applet --install "$PLASMOID_DEST" 2>/dev/null || \
    kpackagetool6 --type Plasma/Applet --upgrade "$PLASMOID_DEST" 2>/dev/null || true
    echo -e "${GREEN}  ✓ Plasmoid enregistré auprès de Plasma${RESET}"
elif command -v kpackagetool5 &>/dev/null; then
    kpackagetool5 --type Plasma/Applet --install "$PLASMOID_DEST" 2>/dev/null || \
    kpackagetool5 --type Plasma/Applet --upgrade "$PLASMOID_DEST" 2>/dev/null || true
fi

# ── Résumé ────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${GREEN}╔════════════════════════════════════════════╗"
echo "║  ✅  Installation terminée !               ║"
echo "╚════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${BOLD}Prochaines étapes :${RESET}"
echo -e "  1. Faites un clic droit sur votre bureau ou panneau KDE"
echo -e "  2. → \"Ajouter des widgets\" → cherchez ${CYAN}\"Polestar Hub\"${RESET}"
echo -e "  3. Faites glisser le widget sur le panneau ou bureau"
echo ""
echo -e "${BOLD}Vérification du service :${RESET}"
echo -e "  ${CYAN}systemctl --user status polestar-plasmoid${RESET}"
echo -e "  ${CYAN}journalctl --user -u polestar-plasmoid -f${RESET}"
echo ""
echo -e "${BOLD}Climatisation à distance :${RESET}"
echo -e "  ${CYAN}$VENV_PYTHON ~/.local/share/polestar-plasmoid/polestar_climate.py start${RESET}"
echo -e "  ${CYAN}$VENV_PYTHON ~/.local/share/polestar-plasmoid/polestar_climate.py stop${RESET}"
echo ""
echo -e "${YELLOW}⚠  Si le daemon ne démarre pas immédiatement, patientez 30s ou lancez :${RESET}"
echo -e "  ${CYAN}systemctl --user restart polestar-plasmoid${RESET}"
