# 🚗 Polestar Hub — KDE Plasma Widget

Un plasmoid élégant pour KDE Plasma (5 & 6) permettant de suivre l'état de votre Polestar en temps réel.

![Interface](plasmoid/contents/images/polestar_car.jpg)

## ✨ Fonctionnalités
- **Batterie** : Pourcentage, autonomie restante et estimation à 100%.
- **Recharge** : État de connexion, puissance de charge (kW) et temps restant.
- **Odomètre** : Kilométrage total et trajet automatique.
- **Santé** : Alertes entretien, liquide de frein et rappels de service.
- **Auto-détection** : Trouve automatiquement votre véhicule (VIN) à partir de vos identifiants.

## 🚀 Installation

### 1. Prérequis
Assurez-vous d'avoir Python 3 et les outils de développement nécessaires :
- **Arch/CachyOS** : `sudo pacman -S python-pip python-venv`
- **Fedora** : `sudo dnf install python3-pip`
- **Ubuntu/Kubuntu** : `sudo apt install python3-pip python3-venv`

### 2. Installation automatique
Clonez le dépôt et lancez le script d'installation :
```bash
git clone https://github.com/votre-compte/polestar-plasmoid.git
cd polestar-plasmoid
chmod +x install.sh
./install.sh
```
Le script s'occupera de créer l'environnement virtuel, d'installer les dépendances (`pypolestar`, `httpx`), de configurer le service systemd et d'installer le widget.

## 🛠️ Utilisation
- **Ajouter le widget** : Clic droit sur votre bureau ou panneau > "Ajouter des widgets" > Cherchez "Polestar Hub".
- **Logs du daemon** : `journalctl --user -u polestar-plasmoid -f`
- **Redémarrer** : `systemctl --user restart polestar-plasmoid`

## 🗑️ Désinstallation
```bash
chmod +x uninstall.sh
./uninstall.sh
```

## ⚖️ Licence
GPL-2.0-only. Dépend de la bibliothèque non-officielle [pypolestar](https://github.com/pypolestar/pypolestar).
