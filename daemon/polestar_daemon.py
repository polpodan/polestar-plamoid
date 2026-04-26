#!/usr/bin/env python3
"""
Polestar KDE Plasmoid Daemon v1.4
- Support pypolestar 0.7.0+ (Models based)
- Auto-détection VIN robuste via get_available_vins()
- Serveur HTTP local sur port 47268 (GET /data, POST /config)
"""

import asyncio
import json
import logging
import sys
import signal
import threading
from datetime import datetime, timezone
from pathlib import Path
from http.server import BaseHTTPRequestHandler, HTTPServer

# ─── Chemins ──────────────────────────────────────────────────────────────────
CONFIG_FILE = Path.home() / ".config"  / "polestar-plasmoid" / "config.json"
DATA_FILE   = Path.home() / ".local"   / "share" / "polestar-plasmoid" / "data.json"
LOG_FILE    = Path.home() / ".local"   / "share" / "polestar-plasmoid" / "daemon.log"

REFRESH_INTERVAL = 300  # 5 minutes

# ─── Logging ──────────────────────────────────────────────────────────────────
DATA_FILE.parent.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("polestar-daemon")


# ─── Helpers JSON ─────────────────────────────────────────────────────────────
def write_status(status: str, error: str = ""):
    payload = {"status": status, "last_update": datetime.now(timezone.utc).isoformat()}
    if error:
        payload["error"] = error
    DATA_FILE.write_text(json.dumps(payload, indent=2))


def write_data(car_info, telematics, username):
    battery  = telematics.battery
    odometer = telematics.odometer
    health   = telematics.health

    def safe_str(val):
        if val is None: return None
        s = str(val)
        return s.split('.')[-1] if '.' in s else s

    data = {
        "status": "ok",
        "last_update": datetime.now(timezone.utc).isoformat(),
        "car": {
            "vin":              getattr(car_info, "vin", None),
            "username":         username,
            "model":            getattr(car_info, "model_name", "Polestar"),
            "model_year":       getattr(car_info, "model_year", None),
            "software_version": getattr(car_info, "software_version", None),
        },
        "battery": {
            "level_pct":              getattr(battery, "battery_charge_level_percentage", None),
            "range_km":               getattr(battery, "estimated_distance_to_empty_km", None),
            "charging_status":        safe_str(getattr(battery, "charging_status", None)),
            "charger_connected":      safe_str(getattr(battery, "charger_connection_status", None)),
            "charging_power_w":       getattr(battery, "charging_power_watts", None),
            "charging_current_a":     getattr(battery, "charging_current_amps", None),
            "time_to_full_min":       getattr(battery, "estimated_charging_time_to_full_minutes", None),
            "avg_consumption_kwh100": getattr(battery, "average_energy_consumption_kwh_per_100km", None),
            "estimated_full_range_km": getattr(battery, "estimated_full_charge_range_km", None),
            "charge_limit_pct":       getattr(battery, "charging_target_percentage", None),
            "updated": battery.event_updated_timestamp.isoformat()
                       if battery and getattr(battery, "event_updated_timestamp", None) else None,
        },
        "odometer": {
            "km":            round(odometer.odometer_meters / 1000, 1)
                             if odometer and getattr(odometer, "odometer_meters", None) else None,
            "trip_auto_km":  getattr(odometer, "trip_meter_automatic_km", None),
            "trip_manual_km": getattr(odometer, "trip_meter_manual_km", None),
            "avg_speed_kmh": getattr(odometer, "average_speed_km_per_hour", None),
            "updated": odometer.event_updated_timestamp.isoformat()
                       if odometer and getattr(odometer, "event_updated_timestamp", None) else None,
        },
        "health": {
            "service_warning":       safe_str(getattr(health, "service_warning", None)),
            "days_to_service":       getattr(health, "days_to_service", None),
            "distance_to_service_km": getattr(health, "distance_to_service_km", None),
            "brake_fluid":           safe_str(getattr(health, "brake_fluid_level_warning", None)),
            "coolant":               safe_str(getattr(health, "engine_coolant_level_warning", None)),
            "oil":                   safe_str(getattr(health, "oil_level_warning", None)),
            "updated": health.event_updated_timestamp.isoformat()
                       if health and getattr(health, "event_updated_timestamp", None) else None,
        },
    }
    DATA_FILE.write_text(json.dumps(data, indent=2, default=str))
    log.info(
        f"✅ Données OK — {data['car']['model']} | "
        f"Batterie: {data['battery']['level_pct']}% | "
        f"Autonomie: {data['battery']['range_km']} km"
    )


# ─── Auto-détection VIN ───────────────────────────────────────────────────────
def discover_vin(api) -> str | None:
    """
    Tente de récupérer le premier VIN disponible via l'API.
    """
    try:
        vins = api.get_available_vins()
        if vins:
            log.info(f"VIN détecté via get_available_vins(): {vins[0]}")
            return vins[0]
    except Exception as e:
        log.debug(f"Échec get_available_vins: {e}")

    # Fallback pour compatibilité ascendante/descendante
    for attr in ("available_vins", "_cars", "cars", "_vehicles", "vehicles"):
        obj = getattr(api, attr, None)
        if isinstance(obj, (list, set, dict)) and obj:
            vin = next(iter(obj.keys() if isinstance(obj, dict) else obj))
            log.info(f"VIN détecté via api.{attr}: {vin}")
            return vin

    return None


# ─── Serveur HTTP local ───────────────────────────────────────────────────────
def start_http_server():
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass  # silencieux

        def do_GET(self):
            if self.path == "/data":
                try:
                    body = DATA_FILE.read_bytes() if DATA_FILE.exists() \
                           else b'{"status":"loading"}'
                except Exception:
                    body = b'{"status":"error","error":"read failed"}'
                self._respond(200, body, "application/json")
            elif self.path == "/car.jpg":
                img_paths = [
                    Path.home() / ".local/share/plasma/plasmoids/com.polestar.plasmoid/contents/images/polestar_car.jpg",
                    Path.home() / ".local/share/polestar-plasmoid/polestar_car.jpg",
                ]
                img_data = None
                for p in img_paths:
                    if p.exists():
                        img_data = p.read_bytes()
                        break
                if img_data:
                    self._respond(200, img_data, "image/jpeg")
                else:
                    self._respond(404, b"", "image/jpeg")
            else:
                self._respond(404, b'{"status":"not found"}', "application/json")

        def do_POST(self):
            if self.path == "/config":
                content_length = int(self.headers['Content-Length'])
                post_data = self.rfile.read(content_length)
                try:
                    new_conf = json.loads(post_data)
                    # Charger l'ancienne config pour ne pas perdre les champs non envoyés
                    current = json.loads(CONFIG_FILE.read_text()) if CONFIG_FILE.exists() else {}
                    current.update({
                        "username": new_conf.get("username", current.get("username")),
                        "password": new_conf.get("password", current.get("password")),
                        "vin":      new_conf.get("vin", current.get("vin"))
                    })
                    CONFIG_FILE.write_text(json.dumps(current, indent=2))
                    log.info("Configuration mise à jour via le plasmoid.")
                    self._respond(200, b'{"status":"ok"}', "application/json")
                except Exception as e:
                    log.error(f"Erreur mise à jour config: {e}")
                    self._respond(500, json.dumps({"status":"error", "error": str(e)}).encode(), "application/json")
            else:
                self._respond(404, b'{"status":"not found"}', "application/json")

        def _respond(self, code, body, content_type):
            self.send_response(code)
            self.send_header("Content-Type", content_type)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_OPTIONS(self):
            self.send_response(200)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")
            self.end_headers()

    server = HTTPServer(("127.0.0.1", 47268), Handler)
    log.info("Serveur HTTP démarré → http://127.0.0.1:47268/data")
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()


# ─── Boucle principale ────────────────────────────────────────────────────────
async def fetch_loop():
    try:
        from pypolestar import PolestarApi
    except ImportError:
        write_status("error", "pypolestar non installé dans le venv")
        sys.exit(1)

    if not CONFIG_FILE.exists():
        write_status("error", f"Config introuvable: {CONFIG_FILE}")
        sys.exit(1)

    start_http_server()
    write_status("connecting")
    log.info("Daemon Polestar démarré.")

    while True:
        try:
            # Relire la config à chaque cycle
            raw = json.loads(CONFIG_FILE.read_text())
            username = raw["username"]
            password = raw["password"]
            vin = (raw.get("vin") or "").strip() or None
            if vin and vin.lower() in ("null", "none"):
                vin = None

            log.info(f"Connexion API (VIN configuré: {vin or 'aucun — auto-détection'})")

            api = PolestarApi(
                username=username,
                password=password,
                vins=[vin] if vin else None,
            )
            await api.async_init()

            # Auto-détection si VIN absent
            if not vin:
                vin = discover_vin(api)
                if vin:
                    raw["vin"] = vin
                    CONFIG_FILE.write_text(json.dumps(raw, indent=2))
                    log.info(f"VIN sauvegardé dans config: {vin}")
                else:
                    write_status("error", "VIN introuvable automatiquement.")
                    await asyncio.sleep(REFRESH_INTERVAL)
                    continue

            log.info(f"Récupération télémétrie pour VIN {vin}…")
            await api.update_latest_data(vin=vin, update_telematics=True)

            car_info   = api.get_car_information(vin=vin)
            telematics = api.get_car_telematics(vin=vin)
            
            if car_info is None:
                write_status("error", f"VIN '{vin}' non reconnu.")
                await asyncio.sleep(REFRESH_INTERVAL)
                continue

            if telematics is None:
                write_status("error", f"Pas de télémétrie pour VIN {vin}.")
                await asyncio.sleep(REFRESH_INTERVAL)
                continue

            write_data(car_info, telematics, username)

        except Exception as e:
            log.error(f"Erreur: {e}", exc_info=True)
            write_status("error", str(e))

        log.info(f"Prochain rafraîchissement dans {REFRESH_INTERVAL}s…")
        await asyncio.sleep(REFRESH_INTERVAL)


# ─── Mode "once" (test / rafraîchissement manuel) ─────────────────────────────
async def run_once():
    try:
        from pypolestar import PolestarApi
        raw = json.loads(CONFIG_FILE.read_text())
        vin = (raw.get("vin") or "").strip() or None
        api = PolestarApi(username=raw["username"], password=raw["password"],
                          vins=[vin] if vin else None)
        await api.async_init()
        if not vin:
            vin = discover_vin(api)
            if vin:
                raw["vin"] = vin
                CONFIG_FILE.write_text(json.dumps(raw, indent=2))
        if vin:
            await api.update_latest_data(vin=vin, update_telematics=True)
            write_data(api.get_car_information(vin=vin), api.get_car_telematics(vin=vin), raw["username"])
        else:
            write_status("error", "VIN introuvable.")
    except Exception as e:
        write_status("error", str(e))
        log.error(str(e), exc_info=True)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT,  lambda *_: sys.exit(0))

    if len(sys.argv) > 1 and sys.argv[1] == "once":
        asyncio.run(run_once())
    else:
        asyncio.run(fetch_loop())
