#!/usr/bin/env python3
"""Prépare chaque nuit le catalogue du fournisseur IPTV pour VJOD.

Télécharge les films et séries du compte Xtream, retrouve l'identifiant TMDB
des titres qui n'en ont pas (via Seerr, quelques milliers par nuit, mémorisés
d'une nuit à l'autre) et écrit un fichier compact que VJOD lit au lieu
d'interroger le fournisseur depuis chaque appareil.

Aucun mot de passe n'est écrit dans le fichier publié : la lecture se fait
toujours directement chez le fournisseur avec le compte du profil.

Réglages : ~/vjod-catalog/config.json (voir config.example.json).
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


def get_json(url, headers=None, timeout=180):
    req = urllib.request.Request(url, headers={"User-Agent": "VJOD-catalog", **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", errors="replace"))


def fetch_provider(cfg):
    base = cfg["portal"].strip().rstrip("/")
    q = {"username": cfg["username"], "password": cfg["password"]}
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
    cfg = {
        "portal": ask("Adresse du fournisseur Xtream (ex. http://exemple.com:8080)", "portal").rstrip("/"),
        "username": ask("Identifiant Xtream", "username"),
        "password": ask("Mot de passe Xtream (ne s'affiche pas)", "password", secret=True),
        "seerr_url": ask("Adresse de Seerr (ex. https://...), vide pour s'en passer", "seerr_url").rstrip("/"),
        "seerr_api_key": "",
        "languages": old.get("languages", ["FR", "EN", "RU", "CN"]),
        "lookups_per_night": old.get("lookups_per_night", 8000),
        "lookups_per_second": old.get("lookups_per_second", 4),
    }
    if cfg["seerr_url"]:
        cfg["seerr_api_key"] = ask("Clé API Seerr (Paramètres > Général)", "seerr_api_key", secret=True)
    langs = input(f"Langues de la maison, par priorité [{','.join(cfg['languages'])}] : ").strip()
    if langs:
        cfg["languages"] = [l.strip().upper() for l in langs.split(",") if l.strip()]
    missing = [k for k in ("portal", "username", "password") if not cfg[k]]
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
        base = cfg["portal"]
        url = f"{base}/player_api.php?" + urllib.parse.urlencode(
            {"username": cfg["username"], "password": cfg["password"]})
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


def main():
    if "--setup" in sys.argv:
        setup()
        return
    try:
        with open(CONFIG, encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, ValueError) as e:
        sys.exit(f"Réglages illisibles ({CONFIG}) : {e}")
    base, rows = fetch_provider(cfg)
    if not rows:
        sys.exit("Catalogue vide : rien n'est publié, l'ancien fichier reste.")
    enrich(cfg, rows)
    payload = {
        "v": 1,
        "fetchedAt": int(time.time() * 1000),
        "account": account_key(base, cfg["username"]),
        "titles": [[r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7]] for r in rows],
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    tmp = OUT + ".tmp"
    with gzip.open(tmp, "wt", encoding="utf-8", compresslevel=9) as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, OUT)
    with_tmdb = sum(1 for r in rows if r[6])
    log(f"Publié : {len(rows)} titres ({with_tmdb} avec TMDB), {os.path.getsize(OUT) // 1024} Ko → {OUT}")


if __name__ == "__main__":
    main()
