# 🚗 Polestar Hub — Plasmoid KDE/Plasma 6

Widget KDE Plasma qui affiche les informations de votre Polestar directement
sur votre bureau, avec un hub complet accessible d'un clic.

---

## Fonctionnalités

| Fonction | Statut |
|---|---|
| Niveau de batterie (%) | ✅ |
| Autonomie estimée (km) | ✅ |
| Autonomie à 100% estimée | ✅ |
| Statut de charge | ✅ |
| Puissance de charge (kW) | ✅ |
| Temps de charge restant | ✅ |
| Odomètre total | ✅ |
| Trip meter | ✅ |
| Consommation moyenne | ✅ |
| Santé véhicule / prochain service | ✅ |
| **Climatisation à distance** | ⚠️ voir ci-dessous |

---

## Prérequis

- **KDE Plasma 6** (Plasma 5 compatible avec adaptation du `metadata.json`)
- **Python 3.10+**
- **pip install pypolestar httpx**
- Un compte **Polestar ID** (le même que l'app mobile)

---

## Installation rapide

```bash
# Cloner ou extraire le projet
cd polestar-plasmoid

# Lancer l'installation
chmod +x install.sh
./install.sh
```

Le script va :
1. Installer les dépendances Python (`pypolestar`, `httpx`)
2. Vous demander vos identifiants Polestar (stockés en `~/.config/polestar-plasmoid/config.json` avec permissions 600)
3. Démarrer un service systemd qui rafraîchit les données toutes les 5 minutes
4. Installer le plasmoid dans `~/.local/share/plasma/plasmoids/`

Après l'installation : **clic droit sur le panneau → Ajouter des widgets → "Polestar Hub"**

---

## Structure du projet

```
polestar-plasmoid/
├── install.sh                    ← Script d'installation tout-en-un
├── uninstall.sh                  ← Désinstallation propre
├── plasmoid/
│   ├── metadata.json             ← Métadonnées Plasma 6
│   └── contents/
│       ├── ui/
│       │   └── main.qml          ← Interface du widget (QML)
│       └── icons/
│           └── polestar.svg      ← Icône dans le panneau
├── daemon/
│   ├── polestar_daemon.py        ← Service Python (récupère les données)
│   └── polestar_climate.py       ← Contrôle climatisation
└── scripts/
    └── polestar-plasmoid.service ← Service systemd user
```

---

## Architecture

```
[Polestar Cloud API]
        ↓ GraphQL (OAuth2)
[polestar_daemon.py]  ← service systemd (toutes les 5 min)
        ↓ JSON
[~/.local/share/polestar-plasmoid/data.json]
        ↓ XHR (toutes les 10s)
[main.qml — Plasmoid KDE]
```

---

## ⚠️ Climatisation à distance

La commande de climatisation à distance est **expérimentale**.

### Ce que dit la recherche

L'API officielle Polestar utilise deux clients OAuth différents :

| Client | Accès | Usage |
|---|---|---|
| `polmystar` | **Lecture seule** | Données télémétrie (batterie, odomètre…) |
| `polexplore` | **Lecture + écriture** | Climatisation, verrouillage/déverrouillage |

La librairie `pypolestar` utilise `polmystar` (lecture seule). Le script
`polestar_climate.py` tente de s'authentifier via `polexplore`.

### Tester manuellement

```bash
# Démarrer la climatisation
python3 ~/.local/share/polestar-plasmoid/polestar_climate.py start

# Arrêter la climatisation
python3 ~/.local/share/polestar-plasmoid/polestar_climate.py stop

# Voir le résultat
cat ~/.local/share/polestar-plasmoid/climate_status.json
```

### Modèles supportés

D'après les retours de la communauté, le contrôle fonctionne pour :
- Polestar 2 (MY2021+)
- Polestar 3
- Polestar 4

Sur certains modèles ou régions, Polestar peut bloquer les clients non officiels.

---

## Gestion du service

```bash
# Statut
systemctl --user status polestar-plasmoid

# Logs en temps réel
journalctl --user -u polestar-plasmoid -f

# Redémarrer
systemctl --user restart polestar-plasmoid

# Rafraîchissement manuel immédiat
python3 ~/.local/share/polestar-plasmoid/polestar_daemon.py once
```

---

## Modifier l'intervalle de rafraîchissement

Éditez la ligne dans `polestar_daemon.py` :
```python
REFRESH_INTERVAL = 300  # secondes (5 minutes par défaut)
```

⚠️ **Ne pas descendre sous 60 secondes** — Polestar peut bannir les clients qui
appellent trop fréquemment.

---

## Dépannage

**Widget vide / "Daemon non démarré"**
```bash
systemctl --user start polestar-plasmoid
journalctl --user -u polestar-plasmoid -n 50
```

**Erreur d'authentification**
```bash
# Vérifier les credentials
cat ~/.config/polestar-plasmoid/config.json

# Tester manuellement
python3 ~/.local/share/polestar-plasmoid/polestar_daemon.py once
```

**Plasmoid absent dans la liste des widgets**
```bash
kpackagetool6 --type Plasma/Applet --install ~/.local/share/plasma/plasmoids/com.polestar.plasmoid
# Puis redémarrer Plasma :
kquitapp6 plasmashell && kstart plasmashell
```

---

## ⚠️ Avertissements légaux

- Ce projet n'est **pas affilié à Polestar** ni à Volvo Cars
- Utilise une **API non officielle** susceptible de changer sans préavis
- Certaines données peuvent ne pas être disponibles selon le modèle
- Utilisez à vos risques — vos credentials sont stockés localement

---

## Licence

MIT — Inspiré de [pypolestar](https://github.com/pypolestar/pypolestar) (MIT)
