/**
 * Die Rechtstexte der App: Datenschutzerklärung, Nutzungsbedingungen,
 * Impressum, Quellen.
 *
 * WARUM EINE EIGENE DATEI NEBEN strings.ts
 *
 * Aus demselben Grund, aus dem es strings.ts gibt — Prüfbarkeit —, aber
 * getrennt davon: Das hier sind DOKUMENTE, keine Oberflächentexte. Sie sind
 * lang, sie werden am Stück gelesen, und sie müssen ausserhalb der App
 * verfügbar sein: Apple und Google verlangen bei der Einreichung eine
 * Datenschutzerklärung unter einer aufrufbaren Adresse.
 *
 * DIE TEXTE STEHEN HIER UND NICHT IN DEN .md-DATEIEN.
 *
 * Die Markdown-Dateien im Repo werden aus dieser Datei ERZEUGT
 * (scripts/make-legal-docs.ts). Andersherum wäre es der sichere Weg in zwei
 * Fassungen, die auseinanderlaufen — und von zwei Datenschutzerklärungen ist
 * mindestens eine falsch. Ein Test prüft, dass die erzeugten Dateien zum
 * Stand dieser Datei passen.
 *
 * WAS HIER NICHT PASSIEREN DARF
 *
 * Keine Aussage, die der Code nicht hergibt. Jede Zeile über das Verhalten
 * der App ist am Quelltext geprüft, und wo eine Prüfung aussteht, steht das
 * dabei. Eine Datenschutzerklärung, die mehr verspricht als die App hält,
 * ist schlechter als keine — sie ist dann nämlich die Grundlage, an der man
 * gemessen wird.
 *
 * KEINE RECHTSBERATUNG. Diese Texte beschreiben nach bestem Wissen, was die
 * App tut. Ob die Formulierungen den Anforderungen genügen, muss vor einer
 * Veröffentlichung jemand mit einschlägiger Qualifikation prüfen.
 */

/** Ein Abschnitt eines Dokuments. */
export type Abschnitt = {
  readonly titel: string;
  readonly absaetze: readonly string[];
};

export type Dokument = {
  readonly titel: string;
  readonly stand: string;
  /** Ein Satz für die Übersicht und den Kopf der erzeugten Datei. */
  readonly vorspann: string;
  readonly abschnitte: readonly Abschnitt[];
};

/**
 * Stand aller Rechtstexte.
 *
 * Ein gemeinsames Datum und nicht eines je Dokument: Sie beschreiben
 * denselben Softwarestand, und getrennte Daten erwecken den Eindruck, eines
 * davon sei aktueller.
 */
export const RECHTSSTAND = '2026-08-01';

/**
 * Lücken, die niemand ausser dem Betreiber füllen kann.
 *
 * Bewusst als sichtbarer Platzhalter und nicht als leerer String: Ein leeres
 * Feld sieht im erzeugten Dokument wie ein Formatfehler aus, dieser Text sagt,
 * was fehlt. Ein Test verhindert, dass ein Dokument mit Platzhaltern als
 * fertig gilt.
 */
export const AUSZUFUELLEN = '[AUSZUFÜLLEN]';

// --- Impressum ------------------------------------------------------------

/**
 * Impressum.
 *
 * § 5 DDG verlangt für geschäftsmässige Telemedien eine Anbieterkennzeichnung
 * mit ladungsfähiger Anschrift. Ob eine unentgeltliche App ohne jede
 * Monetarisierung darunterfällt, ist eine Frage, die hier nicht entschieden
 * wird — beide App-Stores verlangen ohnehin eine Kontaktmöglichkeit, und ein
 * Impressum zu haben kostet nichts.
 *
 * Die Angaben kann nur der Betreiber machen. Sie werden hier NICHT erfunden.
 */
export const IMPRESSUM: Dokument = {
  titel: 'Impressum',
  stand: RECHTSSTAND,
  vorspann: 'Anbieterkennzeichnung nach § 5 DDG.',
  abschnitte: [
    {
      titel: 'Anbieter',
      absaetze: [
        `Name: ${AUSZUFUELLEN}`,
        `Anschrift: ${AUSZUFUELLEN}`,
        `E-Mail: ${AUSZUFUELLEN}`,
        'Eine ladungsfähige Anschrift ist Pflicht. Ein Postfach genügt dafür ' +
        'nicht. Wer keine Privatanschrift veröffentlichen will, kann eine ' +
        'ladungsfähige Anschrift über einen Dienstleister mieten.',
      ],
    },
    {
      titel: 'Verantwortlich für den Inhalt',
      absaetze: [`${AUSZUFUELLEN} (Anschrift wie oben)`],
    },
    {
      titel: 'Umsatzsteuer',
      absaetze: [
        'Die App wird unentgeltlich abgegeben. Eine Umsatzsteuer-Identifikations' +
        'nummer nach § 27a UStG besteht nicht. Sollte sich das ändern, gehört ' +
        'sie hierher.',
      ],
    },
    {
      titel: 'Streitbeilegung',
      absaetze: [
        'Zur Teilnahme an einem Streitbeilegungsverfahren vor einer ' +
        'Verbraucherschlichtungsstelle sind wir weder bereit noch verpflichtet.',
      ],
    },
  ],
};

// --- Datenschutzerklärung -------------------------------------------------

/**
 * Datenschutzerklärung.
 *
 * Jede Tatsachenbehauptung hier ist am Quelltext geprüft. Die Belege stehen
 * in den Kommentaren, damit sich beim nächsten Umbau nachvollziehen lässt,
 * welche Zusage woran hängt.
 */
export const DATENSCHUTZ: Dokument = {
  titel: 'Datenschutzerklärung',
  stand: RECHTSSTAND,
  vorspann:
    'Static verarbeitet personenbezogene Daten ausschliesslich auf dem Gerät ' +
    'und überträgt nichts.',
  abschnitte: [
    {
      titel: 'Das Wichtigste zuerst',
      absaetze: [
        'Es gibt keinen Server. Die App stellt zur Laufzeit keine ' +
        'Netzwerkverbindung her, sie hat kein Konto, keine Anmeldung, keine ' +
        'Werbung, keine Analyse-Bibliothek und keinen Absturzberichtsdienst.',
        // Beleg: app.config.js entzieht android.permission.INTERNET in allen
        // Profilen ausser 'development'; tests/berechtigungen.test.ts hält das
        // durch. Nachgemessen an einem echten `expo prebuild`.
        'Im ausgelieferten Build ist der App die Internet-Berechtigung ' +
        'entzogen. Sie könnte also keine Verbindung herstellen, selbst wenn ' +
        'sie es versuchte. Das lässt sich in den App-Informationen des Systems ' +
        'nachsehen — Sie müssen uns das nicht glauben.',
        'Ihre Position verlässt das Gerät nicht. Sie wird im Arbeitsspeicher ' +
        'mit einer mitgelieferten Liste verglichen und nicht gespeichert.',
      ],
    },
    {
      titel: 'Verantwortlicher',
      absaetze: [
        `${AUSZUFUELLEN} — die Angaben stehen im Impressum.`,
        'Da keine Daten an uns übermittelt werden, erhalten wir auch keine. ' +
        'Verantwortlicher im Sinne von Art. 4 Nr. 7 DSGVO sind wir gleichwohl ' +
        'für die Verarbeitung, die auf Ihrem Gerät stattfindet.',
      ],
    },
    {
      titel: 'Standortdaten',
      absaetze: [
        'Zweck: Die App vergleicht Ihre Position mit einer im App-Paket ' +
        'mitgelieferten Liste stationärer Messstellen, um rechtzeitig zu ' +
        'warnen. Ohne Standort ist das nicht möglich.',
        'Rechtsgrundlage: Ihre Einwilligung durch die Freigabe des ' +
        'Standortzugriffs, Art. 6 Abs. 1 lit. a DSGVO. Sie können sie ' +
        'jederzeit in den Systemeinstellungen widerrufen; die App verliert ' +
        'dann ihre Warnfunktion, bleibt aber lauffähig.',
        // Beleg: src/location/task.ts hält nur laufzeit.letzterFix (EINE
        // Position). TripState hält gerundete Koordinaten gewarnter Anlagen
        // (cameraKey), nicht die eigene Position. LandZustand hält einen
        // Ländercode. Kein Verlauf.
        'Speicherung: keine. Die App hält jeweils die zuletzt empfangene ' +
        'Position im Arbeitsspeicher, um Entfernung und Fahrtrichtung zu ' +
        'berechnen. Sie führt keinen Verlauf. Beim Beenden der App ist auch ' +
        'diese eine Position weg.',
        'Warum Hintergrundzugriff: Die Warnung muss auch bei ausgeschaltetem ' +
        'Display funktionieren — also in genau dem Zustand, für den die App ' +
        'gebaut ist. Ohne Hintergrundzugriff endet sie, sobald der Bildschirm ' +
        'aus ist. Lehnen Sie ihn ab, läuft die App im Vordergrund weiter.',
      ],
    },
    {
      titel: 'Was auf dem Gerät gespeichert wird',
      absaetze: [
        // Beleg: src/state/store.ts (SETTINGS_KEY, ONBOARDING_KEY) und
        // src/core/log.ts (LOG_STORAGE_KEY). Vollständig — es gibt keine
        // weiteren setItem-Aufrufe im Projekt.
        'Drei Dinge, alle ausschliesslich lokal im App-Speicher:',
        '1. Ihre Einstellungen — Lautstärke, Vorwarnzeit, Sprachansage und ' +
        'die übrigen Schalter. Keine personenbezogenen Angaben.',
        '2. Ob Sie den rechtlichen Hinweis bestätigt haben. Ein einzelner ' +
        'Wert, damit er nicht bei jedem Start erneut erscheint.',
        '3. Ein Fehlerprotokoll mit den letzten 200 Einträgen. Es enthält ' +
        'technische Meldungen — etwa "Audio-Session konnte nicht konfiguriert ' +
        'werden". Es enthält KEINE Koordinaten. Die gröbste Ortsangabe, die ' +
        'darin vorkommen kann, ist ein Ländercode wie "DE", damit sich ein ' +
        'Fehler des Länder-Gates nachvollziehen lässt.',
        'Alle drei löschen Sie, indem Sie die App deinstallieren. Das ' +
        'Fehlerprotokoll lässt sich zusätzlich in den Einstellungen löschen.',
      ],
    },
    {
      titel: 'Der Fahrtenschreiber',
      absaetze: [
        'Die App enthält ein Diagnosewerkzeug, das für eine Testfahrt jede ' +
        'Position mitschreibt. Damit entsteht eine vollständige ' +
        'Bewegungsspur — genau das, was die App sonst nicht tut.',
        // Beleg: STANDARD_SETTINGS.fahrtprotokoll === false in
        // src/core/settings.ts; setzeSettings() in task.ts ruft leere() beim
        // Ausschalten; core/fahrtprotokoll.ts schreibt nirgends auf die Platte.
        'Er ist standardmässig AUS. Sie schalten ihn selbst ein, unter ' +
        'Einstellungen, Diagnose. Die Aufzeichnung liegt nur im ' +
        'Arbeitsspeicher, wird nie auf den Gerätespeicher geschrieben und beim ' +
        'Ausschalten des Schalters gelöscht — nicht bloss beendet, gelöscht.',
        'Solange er läuft, können Sie die Aufzeichnung über die Teilen-' +
        'Funktion des Systems weitergeben. Dabei entscheiden SIE, wohin. Die ' +
        'App übergibt den Text an das Betriebssystem und verschickt nichts von ' +
        'sich aus. Was Sie damit tun, liegt ausserhalb unseres Einflusses; ' +
        'die Datei enthält eine vollständige Bewegungsspur, gehen Sie ' +
        'entsprechend damit um.',
      ],
    },
    {
      titel: 'Berechtigungen und wozu',
      absaetze: [
        'Standort, auch im Hintergrund: der Zweck der App.',
        'Vordergrunddienst und Benachrichtigung (Android): Ohne die dauerhaft ' +
        'sichtbare Benachrichtigung beendet Android die Standortverfolgung.',
        'Audio-Einstellungen, Wach-Sperre, Vibration: für Ansage und Warnung.',
        // Beleg: app.config.js, IMMER_ENTZOGEN und NUR_ENTWICKLUNG.
        'Ausdrücklich ENTZOGEN sind im ausgelieferten Build: Internet, ' +
        'Mikrofon, Gerätespeicher, Standortdaten aus fremden Fotos und das ' +
        'Bildschirm-Overlay. Mehrere davon werden von verwendeten ' +
        'Bibliotheken automatisch angefordert; wir nehmen sie wieder heraus.',
      ],
    },
    {
      titel: 'Empfänger, Drittland, automatisierte Entscheidungen',
      absaetze: [
        'Es gibt keine Empfänger. Es findet keine Übermittlung in ein ' +
        'Drittland statt. Es findet keine automatisierte Entscheidungsfindung ' +
        'im Sinne von Art. 22 DSGVO statt.',
        'Der Bezug der App über den App Store oder Google Play ist ein ' +
        'Vorgang zwischen Ihnen und dem jeweiligen Anbieter. Welche Daten ' +
        'dabei anfallen, richtet sich nach dessen Datenschutzerklärung; wir ' +
        'erhalten davon keine Kenntnis.',
      ],
    },
    {
      titel: 'Ihre Rechte',
      absaetze: [
        'Ihnen stehen die Rechte aus Art. 15 bis 21 DSGVO zu: Auskunft, ' +
        'Berichtigung, Löschung, Einschränkung, Datenübertragbarkeit und ' +
        'Widerspruch. Dazu das Recht auf Beschwerde bei einer ' +
        'Aufsichtsbehörde, Art. 77 DSGVO.',
        'In der Praxis laufen die meisten davon ins Leere, und zwar zu Ihren ' +
        'Gunsten: Wir haben keine Daten über Sie, über die wir Auskunft geben ' +
        'oder die wir löschen könnten. Alles, was die App speichert, liegt auf ' +
        'Ihrem Gerät und untersteht Ihnen — löschbar in den Einstellungen oder ' +
        'durch Deinstallation.',
      ],
    },
    {
      titel: 'Änderungen',
      absaetze: [
        'Ändert sich das Verhalten der App, ändert sich diese Erklärung mit. ' +
        `Der Stand steht oben (${RECHTSSTAND}). Da die App keine Verbindung ` +
        'herstellt, erfahren Sie von einer Änderung über das App-Update.',
      ],
    },
  ],
};

// --- Nutzungsbedingungen --------------------------------------------------

export const NUTZUNGSBEDINGUNGEN: Dokument = {
  titel: 'Nutzungsbedingungen',
  stand: RECHTSSTAND,
  vorspann:
    'Was Static leistet, was nicht, und wer wofür verantwortlich ist.',
  abschnitte: [
    {
      titel: 'Was die App ist',
      absaetze: [
        'Static warnt vor STATIONÄREN Messstellen aus einem Datensatz, der ' +
        'vollständig im App-Paket liegt. Sie ist unentgeltlich und wird ohne ' +
        'Gewährleistung abgegeben.',
      ],
    },
    {
      titel: 'Was die App ausdrücklich NICHT leistet',
      absaetze: [
        'Keine Warnung vor mobilen Messstellen. Sie sind in den Daten nicht ' +
        'enthalten und können es nicht sein.',
        'Keine Vollständigkeit. Der Datensatz stammt aus OpenStreetMap und ' +
        'wird ehrenamtlich gepflegt. Die Abdeckung ist regional sehr ' +
        'unterschiedlich — zwischen einzelnen Bundesländern um mehr als das ' +
        'Zwanzigfache. Eine ausbleibende Warnung bedeutet NICHT, dass keine ' +
        'Anlage steht.',
        'Keine Aktualität. Eine abgebaute Anlage verschwindet erst aus den ' +
        'Daten, wenn jemand sie austrägt. Eine neue erscheint erst, wenn ' +
        'jemand sie einträgt.',
        'Keine Richtungssicherheit. Bei rund zwei Dritteln der Anlagen fehlt ' +
        'die überwachte Fahrtrichtung; dort wird richtungsunabhängig gewarnt, ' +
        'auch auf der Gegenfahrbahn.',
        'Keine Navigation, keine Karte, keine Routenplanung.',
      ],
    },
    {
      titel: 'Ihre Verantwortung als Fahrzeugführer',
      absaetze: [
        'Massgeblich ist die Beschilderung, nicht die App. Wer sich auf eine ' +
        'Warnung verlässt, die ausbleibt, fährt trotzdem zu schnell.',
        'Die Bedienung während der Fahrt ist Ihre Sache und Ihr Risiko. Die ' +
        'App ist so gebaut, dass sie im Stand eingerichtet und danach nicht ' +
        'mehr angefasst werden muss.',
        'Ob Sie die App während der Fahrt betreiben dürfen, richtet sich nach ' +
        'dem Recht des Landes, in dem Sie fahren. In Deutschland, Österreich ' +
        'und der Schweiz ist dem Fahrzeugführer der Betrieb eines Geräts, das ' +
        'Verkehrsüberwachungsmassnahmen anzeigt, untersagt. Die App weist Sie ' +
        'dort dauerhaft darauf hin; die Entscheidung treffen Sie.',
      ],
    },
    {
      titel: 'Keine Rechtsberatung',
      absaetze: [
        'Die Angaben zur Rechtslage in der App und in diesen Dokumenten sind ' +
        'nach bestem Wissen zusammengestellt und ausdrücklich keine ' +
        'Rechtsberatung. Massgeblich ist allein der Gesetzestext in der ' +
        'jeweils geltenden Fassung. Für einzelne Länder ist die Lage in ' +
        'diesem Projekt als strittig oder ungeklärt vermerkt; wo sie ' +
        'ungeklärt ist, warnt die App nicht.',
      ],
    },
    {
      titel: 'Haftung',
      absaetze: [
        'Für Schäden, die auf einer fehlenden, verspäteten oder falschen ' +
        'Warnung beruhen, wird keine Haftung übernommen. Das gilt ' +
        'insbesondere für Bussgelder, Punkte und Fahrverbote.',
        'Unberührt bleibt die Haftung für Vorsatz und grobe Fahrlässigkeit ' +
        'sowie für Schäden aus der Verletzung des Lebens, des Körpers oder ' +
        'der Gesundheit.',
      ],
    },
    {
      titel: 'Daten und Lizenz',
      absaetze: [
        'Die Blitzerdaten stammen aus OpenStreetMap, © OpenStreetMap-' +
        'Mitwirkende, und stehen unter der Open Database License (ODbL) 1.0. ' +
        'Der mitgelieferte Datensatz ist eine daraus abgeleitete Datenbank ' +
        'und steht deshalb ebenfalls unter dieser Lizenz.',
        'Wenn Sie den Datensatz weitergeben oder daraus einen eigenen ' +
        'ableiten, treffen Sie die Pflichten der ODbL — insbesondere ' +
        'Namensnennung und Weitergabe unter gleichen Bedingungen.',
      ],
    },
  ],
};

// --- Quellen --------------------------------------------------------------

/**
 * Quellen und Referenzen.
 *
 * Jede fachliche Aussage der App hat eine Quelle, und die steht hier. Das ist
 * nicht Fleiss, sondern die Bedingung dafür, dass sich eine Angabe später
 * prüfen lässt — bei den Rechtsangaben sogar die Bedingung dafür, dass man
 * sie überhaupt machen darf.
 */
export const QUELLEN: Dokument = {
  titel: 'Quellen und Referenzen',
  stand: RECHTSSTAND,
  vorspann: 'Woher die Daten und die Angaben in dieser App stammen.',
  abschnitte: [
    {
      titel: 'Standorte der Messstellen',
      absaetze: [
        'OpenStreetMap, © OpenStreetMap-Mitwirkende, Open Database License ' +
        '(ODbL) 1.0 — https://opendatacommons.org/licenses/odbl/1-0/',
        'Abgefragt über die Overpass-API. Berücksichtigt werden ' +
        'highway=speed_camera sowie Enforcement-Relationen; bei letzteren wird ' +
        'die als "device" verknüpfte Anlage verwendet und nicht der ' +
        'Mittelpunkt der Relation, der im Extremfall über einen Kilometer ' +
        'daneben liegt.',
        'Stand und Umfang des mitgelieferten Datensatzes stehen in der App ' +
        'unter "Datenquelle".',
      ],
    },
    {
      titel: 'Landesgrenzen für die Länder-Erkennung',
      absaetze: [
        'Natural Earth, Admin 0 Countries, Massstab 1:10 Mio. — Public ' +
        'Domain, https://www.naturalearthdata.com/',
        'Bewusst NICHT OpenStreetMap: Die Umrisse wären sonst eine abgeleitete ' +
        'Datenbank im Sinne der ODbL, und das Länder-Gate hinge damit an einer ' +
        'Lizenz mit Weitergabepflicht.',
        'Die Linien sind vereinfacht — an Landgrenzen auf 200 m, an Küsten auf ' +
        '500 m. Der Schwellwert, ab dem die App nach einem Grenzübertritt ' +
        'umschaltet, ist daraus abgeleitet und beträgt das Doppelte der ' +
        'Grenztoleranz.',
      ],
    },
    {
      titel: 'Rechtslage in den einzelnen Ländern',
      absaetze: [
        'ADAC, Juristische Zentrale: Übersicht Radarwarner und Blitzer-Apps ' +
        'im Ausland, Stand 5/2025, ausdrücklich ohne Gewähr.',
        'Wo diese Quelle sich mit anderen Angaben widerspricht, ist das im ' +
        'Projekt als "strittig" vermerkt und der Widerspruch benannt statt ' +
        'aufgelöst. Wo sie keine Aussage zur Funktion gespeicherter Standorte ' +
        'trifft, gilt die Lage als ungeklärt — und dort warnt die App nicht.',
      ],
    },
    {
      titel: 'Zitierte Normen und Entscheidungen',
      absaetze: [
        'Deutschland: § 23 Abs. 1c StVO; Nummer 247 des Bussgeldkatalogs ' +
        '(75 Euro, ein Punkt). OLG Karlsruhe, Beschluss vom 07.02.2023, ' +
        'Az. 2 ORbs 35 Ss 9/23 — die Ordnungswidrigkeit des Fahrers liegt auch ' +
        'vor, wenn der Beifahrer bedient und der Fahrer sich die Warnung ' +
        'zunutze macht.',
        'Österreich: § 98a KFG.',
        'Schweiz: Art. 57b SVG.',
        'Frankreich: Regelung seit dem 03.01.2012 — zulässig ist nur der ' +
        'Hinweis auf einen Gefahrenbereich mit Mindestlänge (300 m innerorts, ' +
        '2000 m Landstrasse, 4000 m Autobahn), nicht der Hinweis auf eine ' +
        'einzelne Messstelle.',
        'Alle Angaben sind Zusammenfassungen und ersetzen den Gesetzestext ' +
        'nicht.',
      ],
    },
    {
      titel: 'Berechnungen',
      absaetze: [
        'Tacho-Abweichung: UNECE-Regelung Nr. 39. Die Anzeige eines ' +
        'Fahrzeugtachos darf nie weniger als die tatsächliche Geschwindigkeit ' +
        'zeigen und höchstens 0,1 × v + 4 km/h darüber liegen. Die Angabe ' +
        'erscheint nur im Erklärtext, sie löst nichts aus.',
        'Nacht-Erkennung für die Bildschirmhelligkeit: NOAA-Sonnenstands' +
        'algorithmus in der üblichen vereinfachten Form. Als Nacht gilt ein ' +
        'Sonnenstand unter −6 Grad, also das Ende der bürgerlichen Dämmerung.',
        'Entfernungen: Haversine-Formel auf einer Kugel mit 6 371 km Radius. ' +
        'Der Fehler gegenüber einem Ellipsoid liegt bei den hier ' +
        'vorkommenden Entfernungen unter einem halben Prozent.',
      ],
    },
    {
      titel: 'Was NICHT als Quelle dient',
      absaetze: [
        'Keine Community-Meldungen. Keine kommerziellen Blitzerdatenbanken. ' +
        'Keine mobilen Messstellen. Kein Abgleich mit einem Server — es gibt ' +
        'keinen.',
      ],
    },
  ],
};

/** Alle Dokumente in der Reihenfolge, in der sie angezeigt werden. */
export const DOKUMENTE = [
  NUTZUNGSBEDINGUNGEN,
  DATENSCHUTZ,
  IMPRESSUM,
  QUELLEN,
] as const;

export type DokumentSchluessel = 'nutzung' | 'datenschutz' | 'impressum' | 'quellen';

export const NACH_SCHLUESSEL: Record<DokumentSchluessel, Dokument> = {
  nutzung: NUTZUNGSBEDINGUNGEN,
  datenschutz: DATENSCHUTZ,
  impressum: IMPRESSUM,
  quellen: QUELLEN,
};

/** Dateiname der erzeugten Markdown-Fassung, ohne Verzeichnis. */
export const DATEINAME: Record<DokumentSchluessel, string> = {
  nutzung: 'NUTZUNGSBEDINGUNGEN.md',
  datenschutz: 'DATENSCHUTZ.md',
  impressum: 'IMPRESSUM.md',
  quellen: 'QUELLEN.md',
};

/** Enthält das Dokument noch unausgefüllte Stellen? */
export function hatLuecken(dokument: Dokument): boolean {
  return dokument.abschnitte.some((a) =>
    a.absaetze.some((p) => p.includes(AUSZUFUELLEN)));
}
