import json
import os
import time
from threading import Lock

import requests
from flask import Flask, jsonify, request

app = Flask(__name__)
EPDK_URL = "https://apigateway.epdk.gov.tr/sarjIstasyonlari/"
CACHE_TTL_SECONDS = int(os.environ.get("CACHE_TTL_SECONDS", "43200"))
ALLOWED_BRANDS = {"TESLA", "TRUGO", "ZES", "ESARJ", "SHARZ", "OTOJET", "VOLTRUN"}
_cache = {}
_cache_lock = Lock()


def fetch_brand(brand):
    now = time.time()
    with _cache_lock:
        cached = _cache.get(brand)
        if cached and now - cached["timestamp"] < CACHE_TTL_SECONDS:
            return cached["records"], None, True, cached["timestamp"]

    try:
        response = requests.request(
            "GET", EPDK_URL, data=json.dumps({"markaAdi": brand}),
            headers={"Content-Type": "application/json", "User-Agent": "EVDecision-StationProxy/1.0"},
            timeout=(5, 30),
        )
        if response.status_code != 200:
            return [], f"{brand}: official service returned {response.status_code}", False, None
        payload = response.json()
        records = payload.get("data") if isinstance(payload, dict) else None
        if not isinstance(records, list):
            return [], f"{brand}: invalid catalogue response", False, None
    except (requests.RequestException, ValueError):
        return [], f"{brand}: catalogue request failed", False, None

    now = time.time()
    with _cache_lock:
        _cache[brand] = {"timestamp": now, "records": records}
    return records, None, False, now


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/stations")
def stations():
    requested = request.args.get("brands", "TESLA").upper().split(",")
    brands = list(dict.fromkeys(brand.strip() for brand in requested if brand.strip()))
    if not brands or any(brand not in ALLOWED_BRANDS for brand in brands):
        return jsonify({"error": "Use supported brands only.", "supportedBrands": sorted(ALLOWED_BRANDS)}), 400
    if len(brands) > 3:
        return jsonify({"error": "Request up to three brands at a time."}), 400

    records, errors, cached = [], [], []
    fetched_by_brand = {}
    for brand in brands:
        result, error, was_cached, fetched_at = fetch_brand(brand)
        records.extend(result)
        if error:
            errors.append(error)
        if was_cached:
            cached.append(brand)
        if fetched_at is not None:
            fetched_by_brand[brand] = fetched_at

    return jsonify({
        "source": "EPDK public charging-station catalogue",
        "availability": "unknown",
        "servedAt": int(time.time()),
        "fetchedAt": min(fetched_by_brand.values(), default=None),
        "fetchedAtByBrand": fetched_by_brand,
        "sourceUpdatedAt": None,
        "cachedBrands": cached,
        "partialFailures": errors,
        "stations": records,
    })
