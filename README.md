# website-

Dieses Repository ist eine Werkstatt: pro Branch ein Projekt. Auf **diesem**
Branch entsteht JARVIS — vollständig in [`jarvis/`](jarvis/README.md), so wie
es das Setup-Zip vorsieht. Das ältere Blitzerwarner-Projekt liegt unangetastet
in [`blitzerwarner/`](blitzerwarner/README.md) daneben.

---

## JARVIS

Alles dazu liegt in [`jarvis/`](jarvis/). Die relevanten Dateien:

| Datei | Inhalt |
|---|---|
| [`jarvis/README.md`](jarvis/README.md) | Installation und Start |
| [`jarvis/CLAUDE.md`](jarvis/CLAUDE.md) | Regeln, Stack, Non-Goals |
| [`jarvis/STATUS.md`](jarvis/STATUS.md) | Projektstand — **hier zuerst schauen** |
| [`jarvis/docs/contracts.md`](jarvis/docs/contracts.md) | Verträge, Budgets, Sicherheitsregeln |
| [`jarvis/docs/phases/`](jarvis/docs/phases/) | ein Auftrag je Phase |

```bash
cd jarvis
pip install -r requirements.txt
python -m uvicorn main:app --reload
```

## Blitzerwarner

Älteres, abgeschlossenes Projekt. Siehe
[`blitzerwarner/README.md`](blitzerwarner/README.md).
