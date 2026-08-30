# JARVIS, Phase 10.
#
# Ein Prozess, ein Startbefehl. Kein Multi-Stage-Zirkus: es gibt nichts zu
# kompilieren, und ein zweiter Stage wuerde das Image nicht kleiner machen.
#
# NICHT AUSGEFUEHRT: in der Umgebung, in der diese Datei entstanden ist, war
# kein Docker-Daemon erreichbar. Der Build ist ungeprueft.

FROM python:3.11-slim

# Nicht als root laufen. Kostet zwei Zeilen und nimmt einem Fehler die Wucht.
RUN useradd --create-home --uid 10001 jarvis

WORKDIR /app

# Erst die Abhaengigkeiten, dann der Code: so bleibt die pip-Schicht im
# Cache, solange sich requirements.txt nicht aendert.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY --chown=jarvis:jarvis core ./core
COPY --chown=jarvis:jarvis api ./api
COPY --chown=jarvis:jarvis scripts ./scripts
COPY --chown=jarvis:jarvis main.py index.html weltlage.html ./

# static/ hat hier GEFEHLT - gefunden bei der Verknuepfungspruefung am
# 29.08.2026, von drei Skeptikern bestaetigt. Ohne den Ordner startet der
# Container zwar, liefert aber eine Seite ohne Stylesheet: index.html und
# weltlage.html laden beide /static/system.css, und der Tab "Welt" laeuft
# beim import('/static/globus.js') in einen 404. Wer der README folgt und
# `docker compose up` startet, bekam also ein kaputtes JARVIS - und der
# Grund war in keinem Test sichtbar, weil die Suite gegen den Quellbaum
# laeuft, nicht gegen das Image.
#
# 2,3 MB, davon der groesste Teil das gevendorte Three.js und die
# Laendergeometrie. Beides muss mit: sie kommen bewusst NICHT aus einem CDN.
COPY --chown=jarvis:jarvis static ./static

# Die Datenbank gehoert nicht ins Image, sondern in ein Volume.
RUN mkdir -p /app/data && chown jarvis:jarvis /app/data
VOLUME ["/app/data"]

USER jarvis

# Im Container an 0.0.0.0 binden - sonst ist der Port von aussen nicht
# erreichbar. Die Absicherung uebernimmt das Port-Mapping in
# docker-compose.yml, das nur an 127.0.0.1 veroeffentlicht (0.4.3).
ENV JARVIS_HOST=0.0.0.0 \
    JARVIS_PORT=8000 \
    JARVIS_DB_PATH=/app/data/jarvis.db \
    JARVIS_OUTBOX_PATH=/app/data/outbox.jsonl \
    PYTHONUNBUFFERED=1

EXPOSE 8000

# Gesund heisst: der Server antwortet. Ein 401 ist eine gueltige Antwort -
# /api/health ist tokenpflichtig, und der Container kennt den Token nicht
# unbedingt. Die Logik steht in scripts/healthcheck.py, nicht als
# unleserliche Einzeiler-Kette hier.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["python", "-m", "scripts.healthcheck"]

CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
