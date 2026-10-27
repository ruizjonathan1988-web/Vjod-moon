#!/usr/bin/env python3
"""Prépare chaque nuit le catalogue du fournisseur IPTV pour VJOD.

Le compte du fournisseur est lu dans les réglages du plugin Xtream de
Jellyfin : changer de fournisseur dans Jellyfin suffit, la nuit suivante
le catalogue et le compte publiés suivent, et VJOD avec.

Télécharge les films et séries du compte Xtream, retrouve l'identifiant TMDB
des titres qui n'en ont pas (via Seerr, quelques milliers par nuit, mémorisés
d'une nuit à l'autre) et écrit un fichier compact que VJOD lit au lieu
d'interroger le fournisseur depuis chaque appareil.

Le fichier publié contient le compte du fournisseur (VJOD en a besoin pour
lire les flux) : il est protégé par le mot de passe « HTTP access »
d'Ultra.cc.

Il dépose aussi, dans une collection Jellyfin « VJOD – réglages », le compte
du fournisseur (jamais l'accès HTTP de la seedbox, qui ouvre aussi WebDAV) :
VJOD le lit après la connexion à Jellyfin et se règle seul, sans rien à
saisir sur les appareils.

Réglages : ~/vjod-catalog/config.json (python3 vjod_catalog.py --setup).
Test du dépôt dans Jellyfin seul : python3 vjod_catalog.py --publish-config
Sortie   : ~/www/vjod/catalog.json.gz
"""
import gzip
import json
import os
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request

HOME = os.path.expanduser("~")
BASE_DIR = os.path.join(HOME, "vjod-catalog")
CONFIG = os.path.join(BASE_DIR, "config.json")
MATCHES = os.path.join(BASE_DIR, "tmdb_matches.json")
OUT_DIR = os.path.join(HOME, "www", "vjod")
OUT = os.path.join(OUT_DIR, "catalog.json.gz")

PREFIX = re.compile(r"^\s*[\[\|(]?\s*([A-Z][A-Z0-9\-]{1,9})(?:\s*-\s+|\s*[\]\|)]\s*)(.+)$")
YEAR_IN_NAME = re.compile(r"[\(\[]\s*((?:19|20)\d{2})\s*[\)\]]|\s-\s((?:19|20)\d{2})\s*$")
ANY_YEAR = re.compile(r"(?:19|20)\d{2}")
QUALITY = re.compile(r"\b(?:4k|uhd|fhd|hd|sd|1080p|720p|2160p|multi|vostfr|vf|vo)\b")


def log(msg):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


def s(v):
    return "" if v is None else str(v).strip()


def split_name(raw):
    text = raw.strip()
    m = PREFIX.match(text)
    if not m or not m.group(2).strip():
        return "", text
    return m.group(1), m.group(2).strip()


def year_of(entry, name):
    for key in ("year", "releaseDate", "release_date", "releasedate"):
        m = ANY_YEAR.search(s(entry.get(key)))
        if m:
            return int(m.group(0))
    m = YEAR_IN_NAME.search(name)
    if m:
        return int(m.group(1) or m.group(2))
    return 0


def tmdb_of(entry):
    for key in ("tmdb", "tmdb_id", "tmdbId"):
        v = s(entry.get(key))
        if v.isdigit() and v != "0":
            return v
    return ""


def fold(text):
    text = unicodedata.normalize("NFKD", text)
    return "".join(c for c in text if not unicodedata.combining(c)).lower()


def match_key(name):
    t = fold(name)
    t = re.sub(r"[\(\[][^\)\]]*[\)\]]", " ", t)
    t = re.sub(r"\s-\s(?:19|20)\d{2}\s*$", " ", t)
    t = t.replace("&", " and ")
    t = re.sub(r"[\W_]+", " ", t)
    t = QUALITY.sub(" ", t)
    return re.sub(r"\s+", " ", t).strip()


def search_text(name):
    t = re.sub(r"[\(\[][^\)\]]*[\)\]]", " ", name)
    t = re.sub(r"\s-\s(?:19|20)\d{2}\s*$", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def account_key(base, username):
    """Même empreinte que catalogCacheKey dans VJOD (FNV-1a 32 bits)."""
    h = 0x811C9DC5
    for b in f"{base}|{username}".encode("utf-8"):
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return f"{h:08x}"


def normalize_portal(url):
    """http://Hote:80/ et http://hote donnent la même adresse."""
    u = urllib.parse.urlsplit(url.strip())
    scheme = (u.scheme or "http").lower()
    host = (u.hostname or "").lower()
    port = u.port
    if port and not ((scheme == "http" and port == 80) or (scheme == "https" and port == 443)):
        host = f"{host}:{port}"
    path = u.path.rstrip("/")
    return f"{scheme}://{host}{path}"


def jellyfin_xtream_account():
    """Le compte réglé dans le plugin Xtream de Jellyfin, le plus récemment
    modifié s'il y en a plusieurs (Xtream et Xtream Library). None sinon."""
    import xml.etree.ElementTree as ET
    # Parcours limité aux dossiers de configuration, en sautant les caches,
    # métadonnées et médias de Jellyfin où il se perdrait.
    skip = {"metadata", "cache", "transcodes", "log", "logs", "root",
            "media", "downloads", "www", "movies", "series", "images",
            "collections", "playlists", "trickplay", "subtitles", "node_modules"}
    roots = [".config", ".apps", ".jellyfin", "jellyfin", ".local/share", "apps"]
    paths = []
    for root in roots:
        top = os.path.join(HOME, root)
        if not os.path.isdir(top):
            continue
        base_depth = top.rstrip(os.sep).count(os.sep)
        for dirpath, dirnames, filenames in os.walk(top):
            depth = dirpath.count(os.sep) - base_depth
            if depth >= 6:
                dirnames[:] = []
            else:
                dirnames[:] = [d for d in dirnames if d.lower() not in skip]
            if dirpath.endswith(os.path.join("plugins", "configurations")):
                paths += [os.path.join(dirpath, f) for f in filenames if f.lower().endswith(".xml")]
    found = []
    for path in paths:
            if "xtream" not in os.path.basename(path).lower():
                continue
            try:
                root = ET.parse(path).getroot()
            except (ET.ParseError, OSError):
                continue
            fields = {el.tag.lower(): (el.text or "").strip() for el in root.iter()}
            url = fields.get("baseurl") or fields.get("serverurl") or fields.get("url") or ""
            user = fields.get("username") or ""
            pw = fields.get("password") or ""
            if url.startswith("http") and user and pw and "example.com" not in url:
                found.append((os.path.getmtime(path), path, url, user, pw))
    if not found:
        return None
    found.sort(reverse=True)
    _, path, url, user, pw = found[0]
    return {"portal": url, "username": user, "password": pw, "from": path}


def account(cfg):
    """Le compte à utiliser : celui de Jellyfin quand il est trouvé, sinon
    celui des réglages."""
    if cfg.get("account_source", "jellyfin") == "jellyfin":
        acc = jellyfin_xtream_account()
        if acc:
            log(f"Compte lu dans Jellyfin ({acc['from']}).")
            return acc
        log("Plugin Xtream de Jellyfin introuvable : compte des réglages utilisé.")
    if not (cfg.get("portal") and cfg.get("username") and cfg.get("password")):
        sys.exit("Aucun compte Xtream : ni dans Jellyfin, ni dans les réglages.")
    return {"portal": cfg["portal"], "username": cfg["username"], "password": cfg["password"]}


def get_json(url, headers=None, timeout=180):
    req = urllib.request.Request(url, headers={"User-Agent": "VJOD-catalog", **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", errors="replace"))


def fetch_provider(acc):
    base = normalize_portal(acc["portal"])
    q = {"username": acc["username"], "password": acc["password"]}
    rows, seen = [], set()
    for action, kind, id_key, icon_key in (
        ("get_vod_streams", "m", "stream_id", "stream_icon"),
        ("get_series", "s", "series_id", "cover"),
    ):
        url = f"{base}/player_api.php?" + urllib.parse.urlencode({**q, "action": action})
        log(f"Fournisseur : {action}…")
        data = get_json(url, timeout=600)
        if not isinstance(data, list):
            raise RuntimeError(f"{action} : réponse inattendue")
        for e in data:
            if not isinstance(e, dict):
                continue
            id_ = s(e.get(id_key))
            raw = s(e.get("name"))
            if not id_ or not raw or (kind, id_) in seen:
                continue
            seen.add((kind, id_))
            tag, name = split_name(raw)
            ext = s(e.get("container_extension"))
            rows.append([
                kind, id_, name, tag, s(e.get(icon_key)),
                (ext or "mp4") if kind == "m" else "",
                tmdb_of(e), year_of(e, name),
            ])
        log(f"  {sum(1 for r in rows if r[0] == kind)} titres")
    return base, rows


def load_matches():
    try:
        with open(MATCHES, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_matches(matches):
    tmp = MATCHES + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(matches, f, ensure_ascii=False)
    os.replace(tmp, MATCHES)


def seerr_lookup(cfg, kind, name, year):
    """L'identifiant TMDB d'un titre, ou 0 quand Seerr ne le trouve pas sûrement."""
    query = search_text(name)
    if not query:
        return 0
    url = cfg["seerr_url"].rstrip("/") + "/api/v1/search?query=" + urllib.parse.quote(query, safe="") + "&page=1"
    data = get_json(url, headers={"X-Api-Key": cfg["seerr_api_key"]}, timeout=30)
    want = "movie" if kind == "m" else "tv"
    key = match_key(name)
    for r in data.get("results", []):
        if r.get("mediaType") != want:
            continue
        titles = [r.get("title"), r.get("originalTitle"), r.get("name"), r.get("originalName")]
        if key not in {match_key(t) for t in titles if t}:
            continue
        date = s(r.get("releaseDate") or r.get("firstAirDate"))
        ry = int(date[:4]) if date[:4].isdigit() else 0
        if year and ry and abs(ry - year) > 1:
            continue
        return int(r.get("id") or 0)
    return 0


def enrich(cfg, rows):
    if not cfg.get("seerr_url") or not cfg.get("seerr_api_key"):
        log("Seerr non réglé : pas de recherche TMDB.")
        return
    matches = load_matches()
    budget = int(cfg.get("lookups_per_night", 8000))
    delay = 1.0 / max(1, int(cfg.get("lookups_per_second", 4)))
    langs = [l.upper() for l in cfg.get("languages", [])]
    retry_after = 30 * 86400
    now = int(time.time())

    def mkey(r):
        return f"{r[0]}|{match_key(r[2])}|{r[7]}"

    # Ce qui est déjà connu d'une nuit sur l'autre est appliqué tout de suite.
    todo = []
    for r in rows:
        if r[6]:
            continue
        known = matches.get(mkey(r))
        if known and known[0]:
            r[6] = str(known[0])
        elif not known or now - known[1] > retry_after:
            todo.append(r)
    # Les langues de la maison d'abord, puis les films avant les séries.
    rank = {t: i for i, t in enumerate(langs)}
    todo.sort(key=lambda r: (rank.get(r[3], len(langs)), r[0] != "m"))
    log(f"TMDB : {len(todo)} titres à identifier, {min(budget, len(todo))} cette nuit.")
    done = found = errors = 0
    asked = {}
    for r in todo:
        if done >= budget:
            break
        k = mkey(r)
        if k in asked:
            r[6] = asked[k]
            continue
        try:
            tmdb = seerr_lookup(cfg, r[0], r[2], r[7])
        except Exception as e:  # réseau, quota : on réessaiera la nuit suivante
            errors += 1
            if errors >= 25:
                log(f"Trop d'erreurs Seerr, arrêt pour cette nuit ({e}).")
                break
            time.sleep(2)
            continue
        done += 1
        matches[k] = [tmdb, now]
        asked[k] = str(tmdb) if tmdb else ""
        if tmdb:
            r[6] = str(tmdb)
            found += 1
        if done % 500 == 0:
            save_matches(matches)
            log(f"  {done} cherchés, {found} trouvés")
        time.sleep(delay)
    # Les doublons d'un même titre (même nom, même année) profitent du résultat.
    for r in rows:
        if not r[6]:
            known = matches.get(mkey(r))
            if known and known[0]:
                r[6] = str(known[0])
    save_matches(matches)
    log(f"TMDB : {done} cherchés, {found} trouvés.")


CONFIG_COLLECTION = "VJOD – réglages"


def jellyfin_request(cfg, method, path, body=None, timeout=30):
    url = cfg["jellyfin_url"].rstrip("/") + path
    headers = {
        "User-Agent": "VJOD-catalog",
        "X-Emby-Token": cfg["jellyfin_api_key"],
        "Authorization": f'MediaBrowser Token="{cfg["jellyfin_api_key"]}"',
    }
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read()
    return json.loads(raw.decode("utf-8")) if raw.strip() else None


def config_overview(acc):
    import base64
    payload = {
        "v": 2,
        "provider": {
            "portal": normalize_portal(acc["portal"]),
            "username": acc["username"],
            "password": acc["password"],
        },
    }
    blob = base64.urlsafe_b64encode(
        json.dumps(payload, separators=(",", ":")).encode("utf-8")
    ).decode("ascii").rstrip("=")
    return (
        "Réglages automatiques de VJOD (catalogue IPTV de la seedbox). "
        "Ne pas modifier ni supprimer : la seedbox la met à jour chaque nuit.\n\n"
        f"VJOD-CONFIG:{blob}"
    )


def publish_jellyfin_config(cfg, acc=None):
    """Écrit le compte du fournisseur dans la collection « VJOD – réglages »,
    que VJOD lit après la connexion à Jellyfin."""
    if not (cfg.get("jellyfin_url") and cfg.get("jellyfin_api_key")):
        log("Jellyfin non réglé : les appareils devront être réglés à la main.")
        return False
    q = urllib.parse.urlencode({
        "IncludeItemTypes": "BoxSet", "Recursive": "true",
        "SearchTerm": "VJOD", "Fields": "Overview",
    })
    found = jellyfin_request(cfg, "GET", f"/Items?{q}") or {}
    item_id = next((i["Id"] for i in found.get("Items", []) if i.get("Name") == CONFIG_COLLECTION), None)
    if not item_id:
        created = jellyfin_request(
            cfg, "POST",
            "/Collections?" + urllib.parse.urlencode({"Name": CONFIG_COLLECTION, "IsLocked": "true"}),
        ) or {}
        item_id = created.get("Id")
        if not item_id:
            raise RuntimeError("Jellyfin n'a pas créé la collection")
        log(f"Collection « {CONFIG_COLLECTION} » créée dans Jellyfin.")
    fields = "Overview,Genres,Tags,Studios,People,ProviderIds,Taglines,DateCreated,SortName"
    items = (jellyfin_request(cfg, "GET", "/Items?" + urllib.parse.urlencode(
        {"Ids": item_id, "Fields": fields})) or {}).get("Items", [])
    if not items:
        raise RuntimeError("collection introuvable après création")
    item = items[0]
    overview = config_overview(acc or account(cfg))
    if item.get("Overview") == overview:
        log("Réglages VJOD dans Jellyfin : déjà à jour.")
        return True
    for key in ("Genres", "Tags", "Studios", "People", "Taglines", "GenreItems",
                "ArtistItems", "AlbumArtists", "LockedFields"):
        item.setdefault(key, [])
    item.setdefault("ProviderIds", {})
    item["Overview"] = overview
    jellyfin_request(cfg, "POST", f"/Items/{item_id}", body=item)
    log("Réglages VJOD écrits dans Jellyfin.")
    return True


def check_catalog_url(url):
    """Code HTTP du fichier publié, identifiants compris."""
    import base64
    u = urllib.parse.urlsplit(url)
    clean = urllib.parse.urlunsplit((u.scheme, u.hostname + (f":{u.port}" if u.port else ""), u.path, u.query, ""))
    req = urllib.request.Request(clean, method="HEAD", headers={"User-Agent": "VJOD-catalog"})
    if u.username:
        login = f"{urllib.parse.unquote(u.username)}:{urllib.parse.unquote(u.password or '')}"
        req.add_header("Authorization", "Basic " + base64.b64encode(login.encode()).decode())
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code


def setup():
    """Pose les questions une par une et écrit les réglages."""
    import getpass
    try:
        with open(CONFIG, encoding="utf-8") as f:
            old = json.load(f)
    except (OSError, ValueError):
        old = {}

    def ask(label, key, secret=False, default=""):
        current = old.get(key, default)
        hint = " (laisser vide pour garder l'actuel)" if current else ""
        if secret:
            value = getpass.getpass(f"{label}{hint} : ")
        else:
            shown = f" [{current}]" if current and not secret else ""
            value = input(f"{label}{shown} : ")
        value = value.strip()
        return value if value else current

    print("Réglages du catalogue VJOD (Ctrl+C pour annuler)\n")
    jf = jellyfin_xtream_account()
    if jf:
        print(f"Compte Xtream trouvé dans Jellyfin : {jf['portal']} ({jf['username']})")
        print("Il sera relu chaque nuit : changer de fournisseur dans Jellyfin suffit.\n")
        cfg = {"account_source": "jellyfin", "portal": "", "username": "", "password": ""}
    else:
        print("Plugin Xtream de Jellyfin introuvable : saisis le compte ici.\n")
        cfg = {
            "account_source": "config",
            "portal": ask("Adresse du fournisseur Xtream (ex. http://exemple.com:8080)", "portal").rstrip("/"),
            "username": ask("Identifiant Xtream", "username"),
            "password": ask("Mot de passe Xtream (ne s'affiche pas)", "password", secret=True),
        }
    cfg.update({
        "seerr_url": ask("Adresse de Seerr (ex. https://...), vide pour s'en passer", "seerr_url").rstrip("/"),
        "seerr_api_key": "",
        "languages": [l.strip(" []'\"").upper() for l in old.get("languages", ["FR", "EN", "RU", "CN"]) if l.strip(" []'\"")],
        "lookups_per_night": old.get("lookups_per_night", 8000),
        "lookups_per_second": old.get("lookups_per_second", 4),
    })
    if cfg["seerr_url"]:
        cfg["seerr_api_key"] = ask("Clé API Seerr (Paramètres > Général)", "seerr_api_key", secret=True)
    langs = input(f"Langues de la maison, par priorité [{','.join(cfg['languages'])}] : ").strip()
    if langs:
        cfg["languages"] = [l.strip(" []'\"").upper() for l in langs.split(",") if l.strip(" []'\"")]

    print("\nPour que les appareils de la maison se règlent seuls (via Jellyfin) :")
    cfg["jellyfin_url"] = ask("Adresse de Jellyfin (celle que VJOD utilise)", "jellyfin_url").rstrip("/")
    cfg["jellyfin_api_key"] = ask("Clé d'API Jellyfin (Tableau de bord > Clés d'API)", "jellyfin_api_key", secret=True)
    old_url = urllib.parse.urlsplit(old.get("catalog_url", "")) if old.get("catalog_url") else None
    base_default = ""
    if old_url and old_url.hostname:
        base_default = urllib.parse.urlunsplit((old_url.scheme, old_url.hostname, old_url.path.rsplit("/vjod/", 1)[0], "", ""))
    print("\nAccès HTTP de la seedbox, pour TES appareils seulement (il n'est jamais")
    print("déposé dans Jellyfin : c'est aussi l'accès WebDAV à tes fichiers).")
    http_base = input(f"Adresse « HTTP access » d'Ultra.cc (panneau > Connect){' [' + base_default + ']' if base_default else ''} : ").strip() or base_default
    http_user = input(f"Identifiant HTTP access{' [' + urllib.parse.unquote(old_url.username) + ']' if old_url and old_url.username else ''} : ").strip() \
        or (urllib.parse.unquote(old_url.username) if old_url and old_url.username else "")
    import getpass as _gp
    http_pass = _gp.getpass("Mot de passe HTTP access (laisser vide pour garder l'actuel) : ") \
        or (urllib.parse.unquote(old_url.password) if old_url and old_url.password else "")
    if http_base:
        b = urllib.parse.urlsplit(http_base.rstrip("/"))
        netloc = b.hostname + (f":{b.port}" if b.port else "")
        if http_user:
            netloc = f"{urllib.parse.quote(http_user, safe='')}:{urllib.parse.quote(http_pass, safe='')}@{netloc}"
        cfg["catalog_url"] = urllib.parse.urlunsplit((b.scheme or "https", netloc, b.path.rstrip("/") + "/vjod/catalog.json.gz", "", ""))
    missing = [k for k in ("portal", "username", "password") if not cfg[k]] if cfg["account_source"] == "config" else []
    if missing:
        sys.exit("Il manque : " + ", ".join(missing) + ". Rien n'est enregistré.")
    os.makedirs(BASE_DIR, exist_ok=True)
    fd = os.open(CONFIG, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    os.chmod(CONFIG, 0o600)
    print("\nRéglages enregistrés (lisibles par toi seul).")
    print("Vérification du compte Xtream…")
    try:
        acc = jf or cfg
        base = normalize_portal(acc["portal"])
        url = f"{base}/player_api.php?" + urllib.parse.urlencode(
            {"username": acc["username"], "password": acc["password"]})
        info = get_json(url, timeout=30)
        status = (info.get("user_info") or {}).get("status", "?") if isinstance(info, dict) else "?"
        print(f"  Fournisseur : compte {status}")
    except Exception as e:
        print(f"  Fournisseur injoignable ou identifiants refusés ({e})")
    if cfg["seerr_url"]:
        try:
            get_json(cfg["seerr_url"] + "/api/v1/settings/main",
                     headers={"X-Api-Key": cfg["seerr_api_key"]}, timeout=20)
            print("  Seerr : OK")
        except Exception as e:
            print(f"  Seerr : échec ({e})")
    if cfg.get("catalog_url"):
        try:
            code = check_catalog_url(cfg["catalog_url"])
            print({200: "  Fichier publié : OK",
                   404: "  Fichier publié : pas encore là (normal avant la fin du premier lancement)",
                   401: "  Fichier publié : identifiant ou mot de passe HTTP access refusé"}.get(code, f"  Fichier publié : code {code}"))
        except Exception as e:
            print(f"  Fichier publié : injoignable ({e})")
    if cfg.get("catalog_url"):
        print("\nInvitation pour TES appareils (garde-la pour toi, elle contient ton accès) :")
        print("  moonfin://vjodcatalog?u=" + urllib.parse.quote(cfg["catalog_url"], safe=""))
    if cfg.get("jellyfin_url"):
        try:
            jellyfin_request(cfg, "GET", "/System/Info", timeout=20)
            print("  Jellyfin : OK")
            publish_jellyfin_config(cfg)
            print("  Réglages déposés dans Jellyfin : OK")
        except Exception as e:
            print(f"  Jellyfin : échec ({e})")


def main():
    if "--setup" in sys.argv:
        setup()
        return
    if "--publish-config" in sys.argv:
        with open(CONFIG, encoding="utf-8") as f:
            publish_jellyfin_config(json.load(f))
        return
    try:
        with open(CONFIG, encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, ValueError) as e:
        sys.exit(f"Réglages illisibles ({CONFIG}) : {e}")
    acc = account(cfg)
    base, rows = fetch_provider(acc)
    if not rows:
        sys.exit("Catalogue vide : rien n'est publié, l'ancien fichier reste.")
    enrich(cfg, rows)
    payload = {
        "v": 1,
        "fetchedAt": int(time.time() * 1000),
        "account": account_key(base, acc["username"]),
        "provider": {"portal": base, "username": acc["username"], "password": acc["password"]},
        "titles": [[r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7]] for r in rows],
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    tmp = OUT + ".tmp"
    with gzip.open(tmp, "wt", encoding="utf-8", compresslevel=9) as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, OUT)
    with_tmdb = sum(1 for r in rows if r[6])
    log(f"Publié : {len(rows)} titres ({with_tmdb} avec TMDB), {os.path.getsize(OUT) // 1024} Ko → {OUT}")
    try:
        publish_jellyfin_config(cfg, acc)
    except Exception as e:  # le catalogue est publié quand même
        log(f"Réglages VJOD dans Jellyfin : échec ({e})")


if __name__ == "__main__":
    main()
