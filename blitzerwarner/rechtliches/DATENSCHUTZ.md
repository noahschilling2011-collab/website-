# Datenschutzerklärung

**Static** — Offline-Warner für stationäre Blitzer

Stand: 2026-08-01

Static verarbeitet personenbezogene Daten ausschliesslich auf dem Gerät und überträgt nichts.

> Diese Datei wird aus `app/src/rechtstexte.ts` erzeugt.
> Änderungen gehören dorthin, sonst sind sie beim nächsten Lauf weg.

> **Noch nicht vollständig.** Die mit `[AUSZUFÜLLEN]` markierten
> Stellen kann nur der Betreiber ausfüllen. Solange sie offen sind,
> ist dieses Dokument nicht veröffentlichungsreif.

## Das Wichtigste zuerst

Es gibt keinen Server. Die App stellt zur Laufzeit keine Netzwerkverbindung her, sie hat kein Konto, keine Anmeldung, keine Werbung, keine Analyse-Bibliothek und keinen Absturzberichtsdienst.

Im ausgelieferten Build ist der App die Internet-Berechtigung entzogen. Sie könnte also keine Verbindung herstellen, selbst wenn sie es versuchte. Das lässt sich in den App-Informationen des Systems nachsehen — Sie müssen uns das nicht glauben.

Ihre Position verlässt das Gerät nicht. Sie wird im Arbeitsspeicher mit einer mitgelieferten Liste verglichen und nicht gespeichert.

## Verantwortlicher

[AUSZUFÜLLEN] — die Angaben stehen im Impressum.

Da keine Daten an uns übermittelt werden, erhalten wir auch keine. Verantwortlicher im Sinne von Art. 4 Nr. 7 DSGVO sind wir gleichwohl für die Verarbeitung, die auf Ihrem Gerät stattfindet.

## Standortdaten

Zweck: Die App vergleicht Ihre Position mit einer im App-Paket mitgelieferten Liste stationärer Messstellen, um rechtzeitig zu warnen. Ohne Standort ist das nicht möglich.

Rechtsgrundlage: Ihre Einwilligung durch die Freigabe des Standortzugriffs, Art. 6 Abs. 1 lit. a DSGVO. Sie können sie jederzeit in den Systemeinstellungen widerrufen; die App verliert dann ihre Warnfunktion, bleibt aber lauffähig.

Speicherung: keine. Die App hält jeweils die zuletzt empfangene Position im Arbeitsspeicher, um Entfernung und Fahrtrichtung zu berechnen. Sie führt keinen Verlauf. Beim Beenden der App ist auch diese eine Position weg.

Warum Hintergrundzugriff: Die Warnung muss auch bei ausgeschaltetem Display funktionieren — also in genau dem Zustand, für den die App gebaut ist. Ohne Hintergrundzugriff endet sie, sobald der Bildschirm aus ist. Lehnen Sie ihn ab, läuft die App im Vordergrund weiter.

## Was auf dem Gerät gespeichert wird

Drei Dinge, alle ausschliesslich lokal im App-Speicher:

1. Ihre Einstellungen — Lautstärke, Vorwarnzeit, Sprachansage und die übrigen Schalter. Keine personenbezogenen Angaben.

2. Ob Sie den rechtlichen Hinweis bestätigt haben. Ein einzelner Wert, damit er nicht bei jedem Start erneut erscheint.

3. Ein Fehlerprotokoll mit den letzten 200 Einträgen. Es enthält technische Meldungen — etwa "Audio-Session konnte nicht konfiguriert werden". Es enthält KEINE Koordinaten. Die gröbste Ortsangabe, die darin vorkommen kann, ist ein Ländercode wie "DE", damit sich ein Fehler des Länder-Gates nachvollziehen lässt.

Alle drei löschen Sie, indem Sie die App deinstallieren. Das Fehlerprotokoll lässt sich zusätzlich in den Einstellungen löschen.

## Der Fahrtenschreiber

Die App enthält ein Diagnosewerkzeug, das für eine Testfahrt jede Position mitschreibt. Damit entsteht eine vollständige Bewegungsspur — genau das, was die App sonst nicht tut.

Er ist standardmässig AUS. Sie schalten ihn selbst ein, unter Einstellungen, Diagnose. Die Aufzeichnung liegt nur im Arbeitsspeicher, wird nie auf den Gerätespeicher geschrieben und beim Ausschalten des Schalters gelöscht — nicht bloss beendet, gelöscht.

Solange er läuft, können Sie die Aufzeichnung über die Teilen-Funktion des Systems weitergeben. Dabei entscheiden SIE, wohin. Die App übergibt den Text an das Betriebssystem und verschickt nichts von sich aus. Was Sie damit tun, liegt ausserhalb unseres Einflusses; die Datei enthält eine vollständige Bewegungsspur, gehen Sie entsprechend damit um.

## Berechtigungen und wozu

Standort, auch im Hintergrund: der Zweck der App.

Vordergrunddienst und Benachrichtigung (Android): Ohne die dauerhaft sichtbare Benachrichtigung beendet Android die Standortverfolgung.

Audio-Einstellungen, Wach-Sperre, Vibration: für Ansage und Warnung.

Ausdrücklich ENTZOGEN sind im ausgelieferten Build: Internet, Mikrofon, Gerätespeicher, Standortdaten aus fremden Fotos und das Bildschirm-Overlay. Mehrere davon werden von verwendeten Bibliotheken automatisch angefordert; wir nehmen sie wieder heraus.

## Empfänger, Drittland, automatisierte Entscheidungen

Es gibt keine Empfänger. Es findet keine Übermittlung in ein Drittland statt. Es findet keine automatisierte Entscheidungsfindung im Sinne von Art. 22 DSGVO statt.

Der Bezug der App über den App Store oder Google Play ist ein Vorgang zwischen Ihnen und dem jeweiligen Anbieter. Welche Daten dabei anfallen, richtet sich nach dessen Datenschutzerklärung; wir erhalten davon keine Kenntnis.

## Ihre Rechte

Ihnen stehen die Rechte aus Art. 15 bis 21 DSGVO zu: Auskunft, Berichtigung, Löschung, Einschränkung, Datenübertragbarkeit und Widerspruch. Dazu das Recht auf Beschwerde bei einer Aufsichtsbehörde, Art. 77 DSGVO.

In der Praxis laufen die meisten davon ins Leere, und zwar zu Ihren Gunsten: Wir haben keine Daten über Sie, über die wir Auskunft geben oder die wir löschen könnten. Alles, was die App speichert, liegt auf Ihrem Gerät und untersteht Ihnen — löschbar in den Einstellungen oder durch Deinstallation.

## Änderungen

Ändert sich das Verhalten der App, ändert sich diese Erklärung mit. Der Stand steht oben (2026-08-01). Da die App keine Verbindung herstellt, erfahren Sie von einer Änderung über das App-Update.

---

Keine Rechtsberatung. Diese Texte beschreiben nach bestem Wissen, was die
App tut. Ob die Formulierungen den Anforderungen genügen, muss vor einer
Veröffentlichung jemand mit einschlägiger Qualifikation prüfen.
