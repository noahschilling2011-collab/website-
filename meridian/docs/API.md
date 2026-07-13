# API-Architektur

REST + JSON über das Gateway, Basis-Pfad `/v1`. Realtime (Verkehr/Sync) über
WebSocket `/v1/ws`. Alle Antworten haben `application/json`; Fehler folgen
RFC-9457 (Problem Details).

## Konventionen
- **Auth:** `Authorization: Bearer <accessToken>` (JWT, 15 min). Refresh via
  `POST /v1/auth/refresh`.
- **Idempotenz:** Schreib-Endpunkte akzeptieren `Idempotency-Key`.
- **Caching:** Lesbare Ressourcen liefern `ETag`/`Cache-Control`.
- **Rate-Limit:** Header `X-RateLimit-Remaining`, `Retry-After` bei 429.
- **Geo-Format:** Koordinaten `[lon, lat]` (GeoJSON-Konvention).

## Endpunkte (Auszug)

### Suche / Geocoding
```
GET  /v1/search?q=brandenburger%20tor&near=13.37,52.51&limit=8
GET  /v1/reverse?lon=13.37&lat=52.51
GET  /v1/suggest?q=café&near=...            # Typeahead (Photon)
POST /v1/nl-search   { "query": "Ladesäule mit Café in der Nähe" }   # KI-NLU
```

### Routing
```
POST /v1/route
{
  "mode": "auto" | "bicycle" | "pedestrian" | "transit",
  "waypoints": [[13.37,52.51],[11.58,48.14]],
  "preference": "fastest" | "comfortable" | "eco" | "scenic",
  "departAt": "2026-07-13T09:00:00Z",
  "alternatives": 3,
  "include": ["weather","traffic","poi:fuel","poi:charging"]
}
→ { "routes": [ { "summary": {distance,duration,eta}, "geometry": <polyline6>,
                  "legs":[{maneuvers:[...]}], "score": {...}, "warnings":[...] } ],
    "recommended": 0, "explanation": "…", "weather":[...], "pois":{...} }

POST /v1/matrix        { sources:[...], targets:[...], mode }
POST /v1/isochrone     { center:[lon,lat], mode, minutes:[10,20,30] }
POST /v1/match         { points:[{lon,lat,ts}], mode }   # Map-Matching / GPS-Fix
```

### Kontext an der Route
```
GET  /v1/weather?path=<polyline>&departAt=...
GET  /v1/poi?path=<polyline>&category=fuel|charging|restaurant|hotel&buffer=2000
GET  /v1/traffic?bbox=minLon,minLat,maxLon,maxLat
GET  /v1/incidents?bbox=...
GET  /v1/speedlimit?lon=..&lat=..&heading=..
```

### Karten-Style / Tiles
```
GET  /v1/style/streets.json        # MapLibre Style (proxied, mit Attribution)
GET  /v1/style/satellite.json
# Vektor-/Rasterkacheln direkt vom CDN (nicht über Gateway)
```

### Nutzer, Favoriten, Sync
```
POST /v1/auth/register | /login | /refresh | /logout
GET  /v1/me
GET/POST/PATCH/DELETE  /v1/favorites  /v1/collections  /v1/saved-routes
GET  /v1/sync?since=<cursor>         # Delta-Pull
WSS  /v1/ws                          # Push: sync, traffic, eta-updates
```

### KI
```
POST /v1/ai/rank-routes   { routes:[...], context:{...} }  → Empfehlung + Erklärung
POST /v1/voice/command    { audio | text }  → Intent + Aktion (STT→NLU)
POST /v1/ai/summarize-route { route }        → Kurz-Briefing der Fahrt
```

## Fehlerformat (RFC 9457)
```json
{ "type":"https://meridian/errors/upstream-unavailable",
  "title":"Routing temporär nicht verfügbar",
  "status":503, "detail":"valhalla timeout", "instance":"/v1/route" }
```

## Versionierung
Pfad-Versionierung (`/v1`). Breaking Changes → `/v2` parallel; Deprecation-Header
`Sunset`. GraphQL-Gateway optional für aggregierte Client-Queries (v6+, Roadmap).
