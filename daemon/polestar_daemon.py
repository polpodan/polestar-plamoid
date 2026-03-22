#!/usr/bin/env python3
"""
Polestar KDE Plasmoid Daemon
Récupère les données de la voiture Polestar via l'API non officielle
et les expose dans un fichier JSON lisible par le plasmoid QML.

Auteur: généré pour plasmoid KDE/Plasma 6
"""

import asyncio
import json
import logging
import os
import sys
import signal
import time
from datetime import datetime, timezone
from pathlib import Path

# ─── Configuration ────────────────────────────────────────────────────────────
CONFIG_FILE = Path.home() / ".config" / "polestar-plasmoid" / "config.json"
DATA_FILE   = Path.home() / ".local" / "share" / "polestar-plasmoid" / "data.json"
LOG_FILE    = Path.home() / ".local" / "share" / "polestar-plasmoid" / "daemon.log"

REFRESH_INTERVAL = 300  # secondes (5 minutes)

# ─── Logging ──────────────────────────────────────────────────────────────────
DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("polestar-daemon")


def write_error(message: str):
    """Écrit un état d'erreur dans le fichier de données."""
    data = {
        "status": "error",
        "error": message,
        "last_update": datetime.now(timezone.utc).isoformat(),
    }
    DATA_FILE.write_text(json.dumps(data, indent=2, default=str))


def write_data(car_info, telematics):
    """Sérialise et écrit les données de la voiture en JSON."""
    battery = telematics.battery
    odometer = telematics.odometer
    health = telematics.health

    data = {
        "status": "ok",
        "last_update": datetime.now(timezone.utc).isoformat(),
        "car": {
            "vin": car_info.vin,
            "model": car_info.model_name or "Polestar",
            "model_year": getattr(car_info, "model_year", None),
            "software_version": getattr(car_info, "software_version", None),
            "image_url": getattr(car_info, "image_url", None),
        },
        "battery": {
            "level_pct": battery.battery_charge_level_percentage if battery else None,
            "range_km": battery.estimated_distance_to_empty_km if battery else None,
            "charging_status": str(battery.charging_status) if battery else None,
            "charger_connected": str(battery.charger_connection_status) if battery else None,
            "charging_power_w": battery.charging_power_watts if battery else None,
            "charging_current_a": battery.charging_current_amps if battery else None,
            "time_to_full_min": battery.estimated_charging_time_to_full_minutes if battery else None,
            "avg_consumption_kwh100": battery.average_energy_consumption_kwh_per_100km if battery else None,
            "estimated_full_range_km": battery.estimated_full_charge_range_km if battery else None,
            "updated": battery.event_updated_timestamp.isoformat() if battery and battery.event_updated_timestamp else None,
        },
        "odometer": {
            "km": round(odometer.odometer_meters / 1000, 1) if odometer and odometer.odometer_meters else None,
            "trip_auto_km": odometer.trip_meter_automatic_km if odometer else None,
            "trip_manual_km": odometer.trip_meter_manual_km if odometer else None,
            "avg_speed_kmh": odometer.average_speed_km_per_hour if odometer else None,
            "updated": odometer.event_updated_timestamp.isoformat() if odometer and odometer.event_updated_timestamp else None,
        },
        "health": {
            "service_warning": str(health.service_warning) if health else None,
            "days_to_service": health.days_to_service if health else None,
            "distance_to_service_km": health.distance_to_service_km if health else None,
            "brake_fluid": str(health.brake_fluid_level_warning) if health else None,
            "coolant": str(health.engine_coolant_level_warning) if health else None,
            "oil": str(health.oil_level_warning) if health else None,
            "updated": health.event_updated_timestamp.isoformat() if health and health.event_updated_timestamp else None,
        },
    }
    DATA_FILE.write_text(json.dumps(data, indent=2, default=str))
    log.info(f"Données écrites → batterie {data['battery']['level_pct']}%, {data['battery']['range_km']} km")


async def start_http_server():
    """Mini serveur HTTP local sur le port 47268 — lit le fichier JSON et le sert."""
    from http.server import BaseHTTPRequestHandler, HTTPServer
    import threading

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            pass  # Silencieux

        def do_GET(self):
            if self.path == "/data":
                try:
                    content = DATA_FILE.read_bytes() if DATA_FILE.exists() else b'{"status":"loading"}'
                except Exception:
                    content = b'{"status":"error","error":"read failed"}'
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)
            elif self.path == "/climate/start":
                self._run_climate("start")
            elif self.path == "/climate/stop":
                self._run_climate("stop")
            else:
                self.send_response(404)
                self.end_headers()

        def _run_climate(self, action):
            import subprocess
            climate_script = DATA_FILE.parent / "polestar_climate.py"
            venv_python = DATA_FILE.parent / "venv" / "bin" / "python3"
            python_bin = str(venv_python) if venv_python.exists() else sys.executable
            try:
                subprocess.Popen([python_bin, str(climate_script), action])
                resp = b'{"status":"ok"}'
            except Exception as e:
                resp = json.dumps({"status": "error", "error": str(e)}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(resp)

    server = HTTPServer(("127.0.0.1", 47268), Handler)
    log.info("Serveur HTTP démarré sur http://127.0.0.1:47268")
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()


async def fetch_loop():
    """Boucle principale de récupération des données."""
    try:
        from pypolestar import PolestarApi
    except ImportError:
        write_error("pypolestar non installé. Lancez: pip install pypolestar")
        log.error("pypolestar non trouvé. pip install pypolestar")
        sys.exit(1)

    if not CONFIG_FILE.exists():
        write_error("Fichier de configuration absent: " + str(CONFIG_FILE))
        log.error(f"Config introuvable: {CONFIG_FILE}")
        sys.exit(1)

    log.info("Démarrage du daemon Polestar…")
    await start_http_server()
    write_data_status("connecting")

    while True:
        try:
            # Relire la config à chaque cycle (permet de changer le VIN sans redémarrer)
            config = json.loads(CONFIG_FILE.read_text())
            username = config["username"]
            password = config["password"]
            vin = config.get("vin") or None
            # Nettoyer le VIN : enlever espaces, guillemets, "null" en string
            if vin and (vin.strip().lower() in ("null", "none", "")):
                vin = None
            if vin:
                vin = vin.strip()

            log.info(f"Connexion à l'API Polestar (VIN: {vin or 'auto-détection'})…")

            # pypolestar exige vins=[] à la construction — jamais None si on a le VIN
            api = PolestarApi(
                username=username,
                password=password,
                vins=[vin] if vin else None,
            )
            await api.async_init()

            # Auto-détection du VIN si absent
            if not vin:
                # Chercher dans les attributs internes possibles
                discovered = None
                for attr in ("_cars", "cars", "_vehicles"):
                    obj = getattr(api, attr, None)
                    if obj:
                        keys = list(obj.keys()) if isinstance(obj, dict) else []
                        if keys:
                            discovered = keys[0]
                            break

                if discovered:
                    vin = discovered
                    log.info(f"VIN auto-détecté: {vin}")
                    config["vin"] = vin
                    CONFIG_FILE.write_text(json.dumps(config, indent=2))
                else:
                    log.warning("VIN introuvable — vérifiez votre config.json")
                    write_error("VIN introuvable. Ajoutez votre VIN dans ~/.config/polestar-plasmoid/config.json")
                    await asyncio.sleep(REFRESH_INTERVAL)
                    continue

            log.info(f"Récupération télémétriques pour VIN {vin}…")
            await api.update_latest_data(vin=vin, update_telematics=True)

            car_info   = api.get_car_information(vin=vin)
            telematics = api.get_car_telematics(vin=vin)

            if car_info is None:
                log.error(f"get_car_information() a retourné None pour VIN={vin}. VIN incorrect?")
                write_error(f"VIN '{vin}' non reconnu par l'API. Vérifiez votre config.json")
                await asyncio.sleep(REFRESH_INTERVAL)
                continue

            if telematics is None:
                log.error(f"get_car_telematics() a retourné None pour VIN={vin}")
                write_error(f"Pas de télémétrie disponible pour VIN {vin}")
                await asyncio.sleep(REFRESH_INTERVAL)
                continue

            write_data(car_info, telematics)

        except Exception as e:
            log.error(f"Erreur API: {e}", exc_info=True)
            write_error(str(e))

        log.info(f"Prochain rafraîchissement dans {REFRESH_INTERVAL}s…")
        await asyncio.sleep(REFRESH_INTERVAL)


def write_data_status(status: str):
    """Écrit un statut intermédiaire."""
    data = {"status": status, "last_update": datetime.now(timezone.utc).isoformat()}
    DATA_FILE.write_text(json.dumps(data, indent=2))


def handle_signal(sig, frame):
    log.info("Signal reçu, arrêt du daemon.")
    sys.exit(0)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    # Support d'une commande "once" pour rafraîchissement ponctuel
    if len(sys.argv) > 1 and sys.argv[1] == "once":
        REFRESH_INTERVAL = 0
        async def run_once():
            try:
                from pypolestar import PolestarApi
                config = json.loads(CONFIG_FILE.read_text())
                vin = config.get("vin")
                api = PolestarApi(username=config["username"], password=config["password"],
                                  vins=[vin] if vin else None)
                await api.async_init()
                await api.update_latest_data(vin=vin, update_telematics=True)
                write_data(api.get_car_information(vin=vin), api.get_car_telematics(vin=vin))
            except Exception as e:
                write_error(str(e))
        asyncio.run(run_once())
    else:
        asyncio.run(fetch_loop())
