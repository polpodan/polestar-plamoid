#!/usr/bin/env python3
"""
Polestar Climate Control Script
Démarre/arrête la climatisation à distance via l'API Polestar.

NOTE IMPORTANTE:
L'API non officielle utilisée par pypolestar (client "polmystar") est en lecture seule.
Le contrôle de la climatisation nécessite le client OAuth "polexplore" qui donne accès
aux mutations GraphQL (climate, lock/unlock).

Ce script tente d'envoyer la commande via GraphQL directement.
Le support varie selon le modèle et la région — ça fonctionne pour Polestar 2/3/4 récents.
"""

import asyncio
import json
import sys
import logging
from pathlib import Path

CONFIG_FILE = Path.home() / ".config" / "polestar-plasmoid" / "config.json"
DATA_FILE   = Path.home() / ".local" / "share" / "polestar-plasmoid" / "climate_status.json"
LOG_FILE    = Path.home() / ".local" / "share" / "polestar-plasmoid" / "climate.log"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.FileHandler(LOG_FILE), logging.StreamHandler()],
)
log = logging.getLogger("polestar-climate")

# Endpoint API Polestar (version polexplore pour les mutations)
OAUTH_URL    = "https://polestarid.eu.polestar.com"
API_URL      = "https://pc-api.polestar.com/eu-north-1/mystar-v2/"
CLIENT_ID_RW = "polexplore"   # Client avec droits d'écriture (climate, lock)
CLIENT_ID_RO = "polmystar"    # Client lecture seule (telemetry)
REDIRECT_URI = "https://www.polestar.com/sign-in-callback"
SCOPE        = "openid profile email customer:attributes"

# Mutation GraphQL pour le démarrage de la climatisation
MUTATION_CLIMATE_START = """
mutation StartClimate($vin: String!) {
  startClimatization(vin: $vin) {
    id
    status
  }
}
"""

MUTATION_CLIMATE_STOP = """
mutation StopClimate($vin: String!) {
  stopClimatization(vin: $vin) {
    id
    status
  }
}
"""


async def get_token_polexplore(username: str, password: str) -> str | None:
    """
    Authentification OAuth2 avec le client polexplore (droits étendus).
    Retourne le token d'accès ou None si échec.
    """
    import httpx
    from urllib.parse import urlencode, urlparse, parse_qs
    import re

    async with httpx.AsyncClient(follow_redirects=True) as client:
        try:
            # Étape 1: obtenir l'URL d'autorisation
            auth_params = {
                "response_type": "code",
                "client_id": CLIENT_ID_RW,
                "redirect_uri": REDIRECT_URI,
                "scope": SCOPE,
            }
            auth_url = f"{OAUTH_URL}/as/authorization.oauth2?{urlencode(auth_params)}"

            # Étape 2: soumettre les credentials
            r = await client.get(auth_url)
            # Extraire le form action
            action_match = re.search(r'action="([^"]+)"', r.text)
            if not action_match:
                log.error("Impossible de trouver le formulaire de login")
                return None

            login_url = action_match.group(1)
            if not login_url.startswith("http"):
                login_url = OAUTH_URL + login_url

            r2 = await client.post(login_url, data={
                "pf.username": username,
                "pf.pass": password,
            }, follow_redirects=False)

            # Chercher le code dans les redirections
            location = r2.headers.get("location", "")
            if "code=" not in location:
                # Suivre les redirections manuellement
                for _ in range(5):
                    if "code=" in location:
                        break
                    r2 = await client.get(location, follow_redirects=False)
                    location = r2.headers.get("location", "")

            code_match = re.search(r"code=([^&]+)", location)
            if not code_match:
                log.error("Code OAuth non trouvé dans la redirection")
                return None

            code = code_match.group(1)

            # Étape 3: échanger le code contre un token
            r3 = await client.post(f"{OAUTH_URL}/as/token.oauth2", data={
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": REDIRECT_URI,
                "client_id": CLIENT_ID_RW,
            })

            token_data = r3.json()
            return token_data.get("access_token")

        except Exception as e:
            log.error(f"Erreur authentification: {e}")
            return None


async def send_climate_command(action: str):
    """
    Envoie une commande de climatisation.
    action: "start" ou "stop"
    """
    try:
        import httpx
    except ImportError:
        result = {"success": False, "error": "httpx non installé (pip install httpx)"}
        DATA_FILE.write_text(json.dumps(result))
        return

    if not CONFIG_FILE.exists():
        result = {"success": False, "error": "Configuration manquante"}
        DATA_FILE.write_text(json.dumps(result))
        return

    config = json.loads(CONFIG_FILE.read_text())
    username = config.get("username")
    password = config.get("password")
    vin      = config.get("vin")

    if not all([username, password, vin]):
        result = {"success": False, "error": "username/password/vin manquants dans la config"}
        DATA_FILE.write_text(json.dumps(result))
        return

    log.info(f"Commande climatisation: {action} pour VIN {vin}")

    # Obtenir le token avec droits étendus
    token = await get_token_polexplore(username, password)
    if not token:
        result = {"success": False, "error": "Échec de l'authentification polexplore"}
        DATA_FILE.write_text(json.dumps(result))
        return

    mutation = MUTATION_CLIMATE_START if action == "start" else MUTATION_CLIMATE_STOP

    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(
                API_URL,
                json={"query": mutation, "variables": {"vin": vin}},
                headers={
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json",
                },
                timeout=15,
            )
            data = resp.json()
            log.info(f"Réponse API: {data}")

            if "errors" in data:
                errors = data["errors"]
                result = {"success": False, "error": str(errors)}
            else:
                result = {"success": True, "action": action, "data": data}

        except Exception as e:
            log.error(f"Erreur requête: {e}")
            result = {"success": False, "error": str(e)}

    DATA_FILE.write_text(json.dumps(result, indent=2))
    return result


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("start", "stop"):
        print("Usage: polestar_climate.py [start|stop]")
        sys.exit(1)

    result = asyncio.run(send_climate_command(sys.argv[1]))
    if result and result.get("success"):
        print(f"✅ Climatisation {sys.argv[1]}ée avec succès")
    else:
        print(f"❌ Échec: {result.get('error') if result else 'Erreur inconnue'}")
        sys.exit(1)
