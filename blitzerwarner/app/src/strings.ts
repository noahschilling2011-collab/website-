/**
 * Alle sichtbaren und hörbaren Texte der App.
 *
 * Der Grund für diese Datei ist nicht Übersetzbarkeit — die App ist einsprachig
 * deutsch. Der Grund ist Prüfbarkeit: Der Rechtshinweis, der Banner und die
 * Lizenzangabe müssen vor einer Veröffentlichung von jemandem gegengelesen
 * werden, der kein JSX liest. Wenn diese Sätze über zwanzig Komponenten
 * verstreut sind, findet sie niemand vollständig.
 *
 * Tonfall: nüchtern. Keine Ausrufezeichen, keine Emojis, kein Marketing. Ein
 * Fehler heisst "Warnung inaktiv", nicht "Ups". Wer bei Tempo 130 einen Satz
 * liest, hat keine Zeit für Stimmung.
 *
 * Handlungsanweisungen stehen im Infinitiv ("Energiesparmodus deaktivieren"),
 * damit die Datei sich nicht zwischen "du" und "Sie" entscheiden muss.
 */
import { LAENDER_GATE, type LandCode } from './config';
import type { CameraKind, Settings } from './types';

// --- gemeinsame Formen ----------------------------------------------------

/**
 * Ein Ausnahmezustand, wie ihn der Nutzer zu sehen bekommt.
 * `handlung` ist Pflicht: Eine Meldung ohne Ausweg ist keine Meldung,
 * sondern eine Beschwerde.
 */
export type Meldung = {
  readonly titel: string;
  readonly text: string;
  readonly handlung: string;
};

/** Ein Eintrag im Einstellungs-Screen. */
export type Feldtext = {
  readonly titel: string;
  readonly hilfe: string;
};

// --- Statuszeile ----------------------------------------------------------

/**
 * Die eine Zeile auf dem Fahrt-Screen, die sagt, ob überhaupt gewarnt wird.
 * Sie ist der einzige Ort, an dem der Nutzer den Unterschied zwischen
 * "läuft" und "läuft nicht" ablesen kann, deshalb ist der Schlüsselraum
 * geschlossen und nicht frei formulierbar.
 */
export type StatusKey =
  | 'aktiv'
  | 'inaktiv'
  | 'landGesperrt'
  | 'sucheGps'
  | 'gpsSchwach'
  | 'keineDatenRegion'
  | 'pausiert'
  | 'gestartet';

const STATUS: Record<StatusKey, string> = {
  aktiv: 'Warnung aktiv',
  inaktiv: 'Warnung inaktiv',
  landGesperrt: 'Warnung in diesem Land abgeschaltet',
  sucheGps: 'Position wird gesucht',
  gpsSchwach: 'Position ungenau',
  keineDatenRegion: 'Keine Blitzerdaten für diese Region',
  pausiert: 'Pausiert',
  gestartet: 'Wird gestartet',
};

// --- Kameraarten ----------------------------------------------------------

/** Bezeichnung auf dem Bildschirm. */
const ART_ANZEIGE: Record<CameraKind, string> = {
  speed: 'Blitzer',
  red_light: 'Rotlichtblitzer',
  both: 'Blitzer und Rotlicht',
  average_speed: 'Abschnittskontrolle',
};

/**
 * Bezeichnung für die Sprachausgabe. Getrennt von der Anzeige, weil
 * gesprochen und gelesen nicht dasselbe ist: "Blitzer und Rotlicht" klingt
 * vorgelesen nach zwei Anlagen.
 */
const ART_ANSAGE: Record<CameraKind, string> = {
  speed: 'Blitzer',
  red_light: 'Rotlichtblitzer',
  both: 'Blitzer mit Rotlichtüberwachung',
  average_speed: 'Abschnittskontrolle',
};

// --- Länder-Banner --------------------------------------------------------

/**
 * Die Länder, in denen ein dauerhafter Hinweis eingeblendet wird. An
 * config.LAENDER_GATE gekoppelt: Verschwindet dort ein Code, bricht hier die
 * Zuweisung — genau das soll passieren, statt dass ein Banner ins Leere zeigt.
 */
export type BannerLand = Extract<LandCode, 'DE' | 'AT' | 'CH' | 'FR'>;

const BANNER: Record<BannerLand, { readonly kurz: string; readonly lang: string }> = {
  DE: {
    kurz: '§ 23 Abs. 1c StVO: Betrieb durch den Fahrer untersagt — 75 Euro, 1 Punkt',
    lang:
      'In Deutschland ist es dem Fahrzeugführer nach § 23 Abs. 1c StVO untersagt, ' +
      'ein Gerät zur Anzeige von Verkehrsüberwachungsmassnahmen zu betreiben oder ' +
      'betriebsbereit mitzuführen. Nach Nummer 247 des Bussgeldkatalogs sind das ' +
      '75 Euro und ein Punkt im Fahreignungsregister. Das OLG Karlsruhe hat mit ' +
      'Beschluss vom 07.02.2023, Az. 2 ORbs 35 Ss 9/23, entschieden, dass das ' +
      'auch gilt, wenn der Beifahrer bedient und der Fahrer sich die Warnung ' +
      'zunutze macht.\n\n' +
      'Das Verbot richtet sich an den Fahrzeugführer, nicht an die App. Die ' +
      'Warnung läuft hier; ob du sie während der Fahrt betreibst, entscheidest ' +
      'du.',
  },
  AT: {
    kurz: 'Österreich: Rechtslage strittig — im ungünstigen Fall bis 10.000 Euro',
    lang:
      'Für Österreich widersprechen sich die Quellen. Die eine Lesart stützt sich ' +
      'auf § 98a KFG und hält die Warnung für untersagt; die andere (ADAC, Stand ' +
      '5/2025) beschreibt als verboten nur Geräte, mit denen Messeinrichtungen ' +
      'beeinflusst oder gestört werden, und nennt Warner mit gespeicherten ' +
      'Standorten ausdrücklich als erlaubt.\n\n' +
      'Dieser Hinweis nennt den ungünstigeren Fall: Trifft er zu, drohen bis zu ' +
      '10.000 Euro und die Einziehung des Geräts — deutlich mehr als in ' +
      'Deutschland. Die Warnung läuft hier; die Entscheidung liegt bei dir.',
  },
  FR: {
    kurz: 'Frankreich: nur Hinweis auf Gefahrenbereiche, keine Entfernungsangabe',
    lang:
      'Frankreich untersagt seit dem 03.01.2012 den deutlichen und ' +
      'unmittelbaren Hinweis auf eine einzelne Messstelle. Zulässig ist nur der ' +
      'allgemeine Hinweis auf einen Gefahrenbereich mit Mindestlänge — 300 m ' +
      'innerorts, 2000 m auf Landstrassen, 4000 m auf Autobahnen.\n\n' +
      'Anders als in Deutschland trifft diese Auflage die APP und nicht nur den ' +
      'Fahrer. Ein Verstoss kostet bis zu 1500 Euro und die Einziehung des ' +
      'Geräts. Die App sagt hier deshalb keine Entfernung an, nennt die Art der ' +
      'Gefahr nicht und gibt pro Bereich genau einen Hinweis.',
  },
  CH: {
    kurz: 'Schweiz, Art. 57b SVG: schon das Mitführen untersagt, Gerät kann eingezogen werden',
    lang:
      'In der Schweiz verbietet Art. 57b SVG das Mitführen und Verwenden von ' +
      'Geräten, die das Erkennen von Verkehrskontrollen erleichtern. Die Quelle ' +
      'nennt die Funktion für gespeicherte Standorte ausdrücklich mit.\n\n' +
      'Das ist die schärfste der drei Regelungen: Untersagt ist nicht erst der ' +
      'Betrieb, sondern schon das Mitführen, und das Gerät kann eingezogen ' +
      'werden. Die Warnung läuft hier; die Entscheidung liegt bei dir.',
  },
};

// --- Ausnahmezustände -----------------------------------------------------

export type FehlerKey =
  | 'gpsVerloren'
  | 'gpsUngenau'
  | 'standortRechtFehlt'
  | 'standortRechtNurVordergrund'
  | 'standortdiensteAus'
  | 'akkuSparmodus'
  | 'hintergrundBeendet'
  | 'neustartWaehrendFahrt'
  | 'bluetoothGetrennt'
  | 'audioBelegt'
  | 'keinSpeicherplatz'
  | 'datensatzUnlesbar';

const FEHLER: Record<FehlerKey, Meldung> = {
  gpsVerloren: {
    titel: 'Kein GPS-Signal',
    text: 'Die Position ist unbekannt. Solange das so bleibt, wird nicht gewarnt.',
    handlung:
      'Gerät mit freier Sicht zum Himmel platzieren. In Tunneln und Tiefgaragen ' +
      'ist das normal und endet von selbst.',
  },
  gpsUngenau: {
    titel: 'Position ungenau',
    text:
      'Die gemeldete Genauigkeit reicht nicht aus, um Fahrtrichtung und ' +
      'Entfernung verlässlich zu bestimmen. Warnungen können ausbleiben.',
    handlung: 'Gerät aus der Ablage unter der Windschutzscheibe hervorholen.',
  },
  standortRechtFehlt: {
    titel: 'Kein Zugriff auf den Standort',
    text: 'Ohne Standortfreigabe kann die App nicht warnen.',
    handlung: 'Standortfreigabe in den Systemeinstellungen erteilen.',
  },
  standortRechtNurVordergrund: {
    titel: 'Standort nur im Vordergrund freigegeben',
    text:
      'Die Warnung endet, sobald der Bildschirm aus ist oder eine andere App ' +
      'in den Vordergrund kommt.',
    handlung:
      'Standortfreigabe in den Systemeinstellungen auf "immer" setzen, oder den ' +
      'Bildschirm während der Fahrt an lassen.',
  },
  standortdiensteAus: {
    titel: 'Standortdienste ausgeschaltet',
    text: 'Das Gerät ermittelt derzeit gar keine Position.',
    handlung: 'Standortdienste in den Systemeinstellungen einschalten.',
  },
  akkuSparmodus: {
    titel: 'Energiesparmodus aktiv',
    text:
      'Das Betriebssystem drosselt im Energiesparmodus die Standortermittlung ' +
      'und beendet Hintergrundaufgaben. Warnungen können verspätet kommen oder ' +
      'ganz ausbleiben.',
    handlung:
      'Energiesparmodus deaktivieren oder die App in den Systemeinstellungen von ' +
      'der Akku-Optimierung ausnehmen.',
  },
  hintergrundBeendet: {
    titel: 'Warnung inaktiv',
    text:
      'Die Standortverfolgung im Hintergrund meldet sich nicht mehr. Es wird ' +
      'nicht gewarnt.',
    handlung: 'App in den Vordergrund holen. Die Verfolgung startet dabei neu.',
  },
  neustartWaehrendFahrt: {
    titel: 'App wurde neu gestartet',
    text:
      'Das Betriebssystem hat die App während der Fahrt beendet und neu ' +
      'gestartet. In der Zwischenzeit wurde nicht gewarnt.',
    handlung:
      'Die Warnung läuft wieder. Wenn das häufiger vorkommt, die App von der ' +
      'Akku-Optimierung ausnehmen.',
  },
  bluetoothGetrennt: {
    titel: 'Bluetooth getrennt',
    text: 'Die Ansage läuft ab jetzt über den Lautsprecher des Geräts.',
    handlung: 'Bluetooth-Verbindung wiederherstellen oder Lautstärke am Gerät prüfen.',
  },
  audioBelegt: {
    titel: 'Ansage nicht hörbar',
    text:
      'Eine andere App belegt die Audioausgabe exklusiv. Die Sprachansage wird ' +
      'unterdrückt, die Anzeige auf dem Bildschirm bleibt.',
    handlung: 'Andere Audio-App beenden oder Ansage abschalten und auf die Anzeige achten.',
  },
  keinSpeicherplatz: {
    titel: 'Kein Speicherplatz',
    text:
      'Einstellungen und Fehlerprotokoll konnten nicht gespeichert werden. Die ' +
      'Warnung läuft weiter, Änderungen gehen beim nächsten Start verloren.',
    handlung: 'Speicherplatz auf dem Gerät freigeben und die App neu starten.',
  },
  datensatzUnlesbar: {
    titel: 'Blitzerdaten nicht lesbar',
    text:
      'Der mitgelieferte Datensatz konnte nicht geladen werden. Es wird nicht ' +
      'gewarnt.',
    handlung: 'App neu installieren. Ein Update setzt den Datensatz neu auf.',
  },
};

// --- Einstellungen --------------------------------------------------------

/**
 * An `Settings` gekoppelt: Wer dort ein Feld ergänzt, bekommt hier einen
 * Typfehler statt eines Schalters ohne Beschriftung.
 */
const EINSTELLUNG_FELD: Record<keyof Settings, Feldtext> = {
  warnDistanceFactor: {
    titel: 'Vorwarnzeit',
    hilfe:
      'Streckt oder staucht die Entfernung, ab der gewarnt wird. Die Entfernung ' +
      'wächst ohnehin mit der Geschwindigkeit.',
  },
  sprachansage: {
    titel: 'Sprachansage',
    hilfe: 'Ohne Ansage warnt nur die Anzeige und, falls eingeschaltet, die Vibration.',
  },
  lautstaerke: {
    titel: 'Lautstärke der Ansage',
    hilfe: 'Wirkt zusätzlich zur Systemlautstärke.',
  },
  rotlichtblitzer: {
    titel: 'Vor Rotlichtblitzern warnen',
    hilfe:
      'Rotlichtblitzer stehen an Kreuzungen und lösen im Stadtverkehr häufiger ' +
      'aus. Wer nur vor Tempomessungen gewarnt werden will, schaltet sie ab.',
  },
  motorradModus: {
    titel: 'Motorradmodus',
    hilfe: 'Lautere Ansage und kräftigere Vibration, für Fahrt mit Helm.',
  },
  haptik: {
    titel: 'Vibration',
    hilfe: 'Kurzes Signal zusätzlich zur Ansage.',
  },
  fahrtprotokoll: {
    titel: 'Fahrt aufzeichnen',
    hilfe:
      'Schreibt für eine Testfahrt jede Position mit, um Aussetzer und ' +
      'Akkuverbrauch messen zu können. Die Aufzeichnung bleibt auf dem Gerät, ' +
      'liegt nur im Arbeitsspeicher und wird beim Ausschalten gelöscht. Im ' +
      'Alltag nicht nötig.',
  },
  tachoFaktor: {
    titel: 'Tacho-Kalibrierung',
    hilfe:
      'Gleicht die Anzeige an den Fahrzeugtacho an. Der GPS-Wert ist die ' +
      'tatsächliche Geschwindigkeit, der Fahrzeugtacho zeigt bauartbedingt mehr.',
  },
};

// --- Zonenmodus -----------------------------------------------------------

/**
 * Ansagetexte für den Zonenmodus (Frankreich).
 *
 * WARUM DIESER EINE KATALOG MEHRSPRACHIG IST, obwohl die App einsprachig
 * deutsch ist: Die Zonenansage folgt der Systemsprache des Geräts, nicht der
 * App-Sprache. Ein rein deutscher Katalog käme an einem französischsprachigen
 * Gerät ungeprüft heraus — und die Auflage, die Gefahr nicht zu benennen,
 * gilt in jeder Sprache. Deshalb stehen alle Varianten hier, wo sie
 * gegengelesen und vom Test erfasst werden.
 *
 * Bewusst ein GETRENNTER Katalog neben STRINGS.ansage und nicht derselbe mit
 * anderer Formulierung: Wer später einen Punkt-Ansagetext ergänzt, soll ihn
 * nicht versehentlich in einer Zone verwenden können. Die Trennung ist die
 * Sicherung, der Test in tests/zone-wortliste.test.ts die Kontrolle.
 *
 * Genannt wird ein Aufmerksamkeitshinweis auf einen Streckenabschnitt — keine
 * Entfernung, keine Richtung, keine Art der Gefahr.
 */
const ZONE_ANSAGE = {
  de: 'Achtungsbereich',
  fr: 'Zone de vigilance',
  en: 'Caution zone',
} as const;

// --- alle Texte -----------------------------------------------------------

export const STRINGS = {
  /** Neutrale Bausteine, die auf mehreren Screens vorkommen. */
  allgemein: {
    appName: 'Static',
    appUntertitel: 'Offline-Warner für stationäre Blitzer',
    weiter: 'Weiter',
    zurueck: 'Zurück',
    schliessen: 'Schliessen',
    abbrechen: 'Abbrechen',
    verstanden: 'Verstanden',
    erneutVersuchen: 'Erneut versuchen',
    systemeinstellungenOeffnen: 'Systemeinstellungen öffnen',
    mehrDazu: 'Mehr dazu',
    unbekannt: '—',
  },

  einheit: {
    kmh: 'km/h',
    meter: 'm',
    kilometer: 'km',
  },

  /** Erster Start, bestätigungspflichtig. */
  onboarding: {
    willkommenTitel: 'Bevor es losgeht',
    willkommenText:
      'Diese App warnt vor stationären Blitzern aus einem Datensatz, der ' +
      'vollständig auf dem Gerät liegt. Sie stellt zur Laufzeit keine ' +
      'Netzwerkverbindung her.',

    grenzenTitel: 'Was die App nicht kann',
    grenzenText:
      'Vor mobilen Messstellen wird nicht gewarnt. Sie sind in den Daten nicht ' +
      'enthalten und können es nicht sein. Der Datensatz stammt aus ' +
      'OpenStreetMap und ist regional unterschiedlich vollständig; eine ' +
      'ausbleibende Warnung bedeutet nicht, dass keine Anlage steht.',

    rechtTitel: 'Rechtlicher Hinweis',
    rechtNorm:
      '§ 23 Abs. 1c StVO untersagt dem Fahrzeugführer, ein technisches Gerät zu ' +
      'betreiben oder betriebsbereit mitzuführen, das dafür bestimmt ist, ' +
      'Verkehrsüberwachungsmassnahmen anzuzeigen oder zu stören. Das umfasst ein ' +
      'Mobiltelefon mit einer entsprechenden App.',
    rechtSanktion:
      'Ein Verstoss wird nach Nummer 247 des Bussgeldkatalogs mit 75 Euro und ' +
      'einem Punkt im Fahreignungsregister geahndet.',
    rechtBeifahrer:
      'Das OLG Karlsruhe hat mit Beschluss vom 07.02.2023, Az. 2 ORbs 35 Ss 9/23, ' +
      'entschieden, dass eine Ordnungswidrigkeit des Fahrers auch dann vorliegt, ' +
      'wenn der Beifahrer die App bedient, sofern der Fahrer das billigt und sich ' +
      'die Warnung zunutze macht. Die Bedienung durch eine andere Person im ' +
      'Fahrzeug ist damit kein Ausweg.',
    rechtFolge:
      'Das Verbot richtet sich an den Fahrzeugführer, nicht an die App. Die ' +
      'Warnung läuft deshalb auch in Deutschland, Österreich und der Schweiz — ' +
      'ob du sie während der Fahrt betreibst, entscheidest du. In diesen drei ' +
      'Ländern blendet die App dauerhaft einen Hinweis mit der jeweiligen Norm ' +
      'ein; er lässt sich nicht abschalten. Ausserhalb richtet sich die ' +
      'Zulässigkeit nach dem jeweiligen nationalen Recht; die Verantwortung ' +
      'dafür trägt der Fahrzeugführer. Wo die Rechtslage ungeklärt ist, warnt ' +
      'die App nicht.',
    rechtKeineBeratung:
      'Diese Zusammenfassung ist nach bestem Wissen erstellt und keine ' +
      'Rechtsberatung. Massgeblich ist allein der Gesetzestext in der jeweils ' +
      'geltenden Fassung.',
    rechtBestaetigung: 'Ich habe den rechtlichen Hinweis gelesen',
    rechtBestaetigenAktion: 'Gelesen und verstanden',
    rechtSpaeterNachlesen: 'Dieser Hinweis steht dauerhaft in den Einstellungen.',

    berechtigungTitel: 'Zugriff auf den Standort',
    berechtigungText:
      'Die App vergleicht die Position mit dem gespeicherten Datensatz. Damit das ' +
      'auch bei ausgeschaltetem Display funktioniert — also in dem Zustand, für ' +
      'den die App gebaut ist — wird der Standortzugriff im Hintergrund benötigt. ' +
      'Die Position wird ausschliesslich auf dem Gerät verarbeitet.',
    berechtigungAnfordern: 'Standortzugriff erlauben',
    berechtigungErteilt: 'Standortzugriff erteilt',
    berechtigungZweiSchritte:
      'Android fragt in zwei Schritten: erst den Zugriff während der Nutzung, ' +
      'danach den im Hintergrund.',

    ablenkungTitel: 'Bedienung während der Fahrt',
    ablenkungText:
      'Die App wird vor Fahrtantritt eingerichtet. Während der Fahrt ist nur die ' +
      'grosse Fläche auf dem Fahrt-Screen bedienbar.',
  },

  /**
   * Dauerhafter Hinweis in DE/AT/CH. Nicht abschaltbar — das ist kein
   * vergessener Schalter, sondern Absicht.
   */
  banner: {
    ...BANNER,
    nichtAbschaltbar: 'Dieser Hinweis lässt sich nicht abschalten.',
  },

  /** Der Screen, der während der Fahrt läuft. */
  fahrt: {
    status: STATUS,
    tachoEinheit: 'km/h',
    tachoUnbekannt: '—',
    tachoQuelle: 'GPS',
    limitZeichenBeschriftung: 'Tempolimit',
    limitUnbekannt: 'Limit unbekannt',
    art: ART_ANZEIGE,
    entfernungBeschriftung: 'Entfernung',
    naechsteAnlage: 'Nächste Anlage',
    keineAnlageInDerNaehe: 'Keine Anlage in Reichweite',
    warnungQuittieren: 'Warnung ausblenden',
    fahrtStarten: 'Fahrt starten',
    fahrtBeenden: 'Fahrt beenden',
    ueberLimit: 'Über dem Limit',
  },

  /**
   * Bausteine der Sprachausgabe. Zusammengesetzt wird in `ansage()`, damit
   * die Reihenfolge an einer Stelle steht und im Test überprüfbar ist.
   */
  ansage: {
    art: ART_ANSAGE,
    entfernungPraefix: 'in',
    meterSingular: 'Meter',
    meterPlural: 'Metern',
    tempoPraefix: 'Tempo',
    /** Ohne bekannte Entfernung, etwa direkt nach einem Positionssprung. */
    ohneEntfernung: 'voraus',
    warnungInaktiv: 'Warnung inaktiv',
    tempolimitUeberschritten: 'Tempolimit überschritten',
  },

  /**
   * Der Watchdog prüft, ob die Hintergrundverfolgung noch lebt. Er ist der
   * einzige Weg, auf dem der Nutzer vom stillen Ausfall erfährt — deshalb
   * hörbar und nicht nur als Zeile.
   */
  watchdog: {
    titel: 'Warnung inaktiv',
    text:
      'Die Standortverfolgung im Hintergrund hat sich zuletzt vor längerer Zeit ' +
      'gemeldet. Es wird nicht gewarnt.',
    handlung: 'App in den Vordergrund holen, damit die Verfolgung neu startet.',
    ansage: 'Warnung inaktiv',
    quittieren: 'Verstanden',
    erneutStarten: 'Verfolgung neu starten',
    statuszeile: 'Warnung inaktiv, zuletzt gemeldet vor',
  },

  fehler: FEHLER,

  /** Leere Zustände. Ein leerer Bildschirm ohne Erklärung ist ein Fehler. */
  leer: {
    keineDatenRegionTitel: 'Keine Blitzerdaten für diese Region',
    keineDatenRegionText:
      'Der mitgelieferte Datensatz enthält für diese Gegend keine Anlagen. Das ' +
      'heisst nicht, dass hier keine stehen — es heisst, dass in OpenStreetMap ' +
      'keine erfasst sind.',
    keineDatenRegionHandlung:
      'Ohne Daten wird hier nicht gewarnt. Ein aktuellerer Datensatz kommt mit ' +
      'dem nächsten App-Update. Bis dahin gilt die Beschilderung.',

    keineWarnungenTitel: 'Keine Warnungen in dieser Fahrt',
    keineWarnungenText: 'Es lag keine bekannte Anlage in Fahrtrichtung voraus.',

    keineFehlerTitel: 'Keine Einträge',
    keineFehlerText: 'Das Fehlerprotokoll ist leer.',

    ausserhalbAbdeckungTitel: 'Ausserhalb des Datensatzes',
    ausserhalbAbdeckungText:
      'Die aktuelle Position liegt ausserhalb des Gebiets, für das Daten ' +
      'mitgeliefert wurden.',
    ausserhalbAbdeckungHandlung: 'Tacho und Tempolimit-Anzeige laufen weiter.',
  },

  /** Einstellungen. */
  einstellungen: {
    titel: 'Einstellungen',
    feld: EINSTELLUNG_FELD,
    abschnittWarnung: 'Warnung',
    abschnittAusgabe: 'Ausgabe',
    abschnittTacho: 'Tacho',
    abschnittDaten: 'Daten',
    abschnittRecht: 'Recht und Lizenz',
    abschnittDiagnose: 'Diagnose',
    fehlerprotokoll: 'Fehlerprotokoll',
    fahrtprotokollExport: 'Fahrtprotokoll teilen',
    fahrtprotokollVerweis:
      'Die Aufzeichnung lässt sich unter "Info" als CSV weitergeben.',
    fahrtprotokollLeer: 'Noch keine Positionen aufgezeichnet',
    fahrtprotokollHilfe:
      'Gibt die Aufzeichnung als CSV weiter — an eine Tabelle, eine Notiz oder ' +
      'per Mail an sich selbst. Die App verschickt nichts von sich aus; sie ' +
      'übergibt den Text an das System und der Nutzer entscheidet, wohin.',
    fahrtprotokollAkkuHinweis:
      'Für die Akkumessung: Akkustand vor und nach der Fahrt aus den ' +
      'Systemeinstellungen ablesen und in die vorbereiteten Zeilen im Kopf der ' +
      'Datei eintragen.',
    fehlerprotokollLoeschen: 'Fehlerprotokoll löschen',
    fehlerprotokollHilfe:
      'Bleibt auf dem Gerät. Wird nirgendwohin übertragen, weil es nichts gibt, ' +
      'wohin übertragen werden könnte.',
    rechtshinweisErneutLesen: 'Rechtlichen Hinweis erneut lesen',
    aufWerkseinstellungen: 'Einstellungen zurücksetzen',
  },

  /** Herkunft und Lizenz der Daten. Pflichtangabe, kein Beiwerk. */
  daten: {
    titel: 'Datenquelle',
    attribution: '© OpenStreetMap-Mitwirkende',
    lizenzName: 'Open Database License (ODbL) 1.0',
    lizenzUrl: 'https://opendatacommons.org/licenses/odbl/1-0/',
    lizenzText:
      'Die Blitzerdaten stammen aus OpenStreetMap, © OpenStreetMap-Mitwirkende, ' +
      'und stehen unter der Open Database License (ODbL) 1.0. Der mitgelieferte ' +
      'Datensatz ist eine daraus abgeleitete Datenbank und steht deshalb ' +
      'ebenfalls unter dieser Lizenz.',
    standPraefix: 'Stand der Daten',
    standUnbekannt: 'Stand der Daten unbekannt',
    umfangPraefix: 'Enthaltene Anlagen',
    qualitaetTitel: 'Wie vollständig die Daten sind',
    qualitaetText:
      'OpenStreetMap wird ehrenamtlich gepflegt. Die Abdeckung ist regional sehr ' +
      'unterschiedlich, und ein abgebauter Blitzer verschwindet erst aus den ' +
      'Daten, wenn ihn jemand einträgt. Bei rund zwei Dritteln der Anlagen fehlt ' +
      'die überwachte Fahrtrichtung; dort wird richtungsunabhängig gewarnt, was ' +
      'zu Warnungen auf der Gegenfahrbahn führen kann.',
    limitHinweis:
      'Das angezeigte Tempolimit stammt aus denselben Daten und ist bei ' +
      'Abschnittskontrollen und richtungsabhängigen Limits nicht immer die für ' +
      'die Messung geltende Grenze.',
  },

  /**
   * Zonenmodus. Gilt derzeit nur für Frankreich.
   *
   * Kein Text in diesem Abschnitt darf ein Wort aus VERBOTENE_ZONENWOERTER
   * enthalten — auch nicht die Bildschirmtexte. Die Regelung betrifft die
   * Ausgabe des Geräts, nicht nur die Stimme.
   */
  zone: {
    ansage: ZONE_ANSAGE,
    /** Statuszeile, wenn der Zonenmodus läuft. */
    aktiv: 'Hinweise für Streckenabschnitte aktiv',
    /**
     * Wenn die Zonendatei für ein Land im Zonenmodus fehlt. Der Nutzer
     * erfährt, dass hier NICHT gewarnt wird — die stille Variante wäre eine
     * App, die "aktiv" meldet und nie etwas sagt.
     */
    datenFehlenTitel: 'Keine Hinweisdaten für dieses Land',
    datenFehlenText:
      'Für dieses Land liegt der Hinweisdatensatz nicht im App-Paket. Es wird ' +
      'hier nichts angesagt.',
    datenFehlenHandlung:
      'App neu installieren. Ein Update bringt den Datensatz mit. Bis dahin gilt ' +
      'die Beschilderung.',
  },

  /**
   * Der Rechtliches-Bereich. Die Dokumente selbst stehen in rechtstexte.ts —
   * hier nur die Beschriftungen drumherum.
   */
  /**
   * Die Umgebungskarte.
   *
   * Der Ton hier ist bewusst zurückhaltend. Diese Karte kann weniger, als
   * das Wort verspricht — sie zeigt keine Strassen. Wer sie mit einer
   * Navigationskarte verwechselt und dann feststellt, dass sie keine ist,
   * hält die App für kaputt statt für ehrlich.
   */
  karte: {
    titel: 'Umgebung',
    oeffnen: 'Umgebung',
    /** Steht über der Karte, nicht klein darunter. */
    keineStrassen:
      'Keine Strassen — die App lädt nichts nach. Gezeichnet wird nur, was im '
      + 'Paket liegt: die erfassten Anlagen und deine Position.',
    radius: 'Umkreis',
    warteAufPosition: 'Warte auf die erste Position.',
    warteAufPositionHilfe:
      'Die Karte braucht einen GPS-Fix. Unter freiem Himmel dauert das ' +
      'meist unter einer Minute; in Gebäuden kann es ausbleiben.',
    keineDaten: 'Kein Datensatz geladen.',
    keineAnlagen: 'Im gewählten Umkreis ist keine Anlage erfasst.',
    keineAnlagenHilfe:
      'Das heisst nicht, dass hier keine steht — nur, dass in ' +
      'OpenStreetMap keine erfasst ist.',
    /** Wird nur gezeigt, wenn wirklich abgeschnitten wurde. */
    abgeschnitten: (wieviele: number, gesamt: number): string =>
      `${gesamt} Anlagen im Umkreis, ${wieviele} davon nicht gezeichnet. ` +
      'Kleineren Umkreis wählen.',
    anlagenImUmkreis: (n: number): string =>
      n === 1 ? '1 Anlage im Umkreis' : `${n} Anlagen im Umkreis`,
    naechste: 'Nächste',
    ichHier: 'Deine Position',
  },

  rechtliches: {
    titel: 'Rechtliches',
    stand: 'Stand',
    oeffnen: 'Rechtliches',
    luecke: 'unvollständig',
    unvollstaendig:
      'Dieses Dokument ist noch nicht vollständig. Die markierten Stellen ' +
      'kann nur der Betreiber ausfüllen; solange sie offen sind, ist es nicht ' +
      'veröffentlichungsreif.',
    meineDaten: 'Meine Daten',
    meineDatenHilfe:
      'Es gibt kein Konto und keinen Server. Auf dem Gerät liegen nur deine ' +
      'Einstellungen, das Fehlerprotokoll und — falls eingeschaltet — das ' +
      'Fahrtprotokoll. Mehr hat die App nicht über dich.',
    datenExport: 'Meine Daten ausgeben',
    datenLoeschen: 'Alle Daten auf diesem Gerät löschen',
    keinKonto:
      'Ein Konto zum Löschen gibt es nicht — es wurde nie eines angelegt. ' +
      'Mit der Deinstallation verschwindet auch der Rest.',
  },

  /** Kurz, weil es wenig zu sagen gibt. */
  datenschutz: {
    titel: 'Datenschutz',
    kurz:
      'Es gibt keinen Server. Deshalb werden keine Daten erhoben und keine ' +
      'übertragen.',
    keinNetz:
      'Die App stellt zur Laufzeit keine Netzwerkverbindung her. Der Datensatz ' +
      'liegt vollständig im App-Paket.',
    /**
     * Nur im ausgelieferten Build wahr. Im Entwicklungsbuild ist die
     * Berechtigung vorhanden, weil der Dev-Client sein JS über das Netz lädt —
     * der Satz wird dort deshalb nicht angezeigt. Was die App nicht beweisen
     * kann, behauptet sie auch nicht.
     */
    keinNetzBewiesen:
      'In diesem Build ist der App die Internet-Berechtigung entzogen. Sie ' +
      'könnte also gar keine Verbindung herstellen — das lässt sich in den ' +
      'App-Informationen des Systems nachsehen.',
    keinMikrofon:
      'Ebenfalls entzogen: Zugriff auf Mikrofon und Gerätespeicher. Die App ' +
      'spielt Töne ab, sie nimmt nichts auf.',
    /**
     * Der Ersatz für keinNetzBewiesen auf iOS und im Entwicklungsbuild.
     *
     * iOS kennt keine Internet-Berechtigung: Jede App darf ins Netz, es gibt
     * nichts zu entziehen und nichts, was der Nutzer in den
     * Systemeinstellungen nachsehen könnte. Der Satz von Android wäre hier in
     * beiden Hälften falsch. Was bleibt, ist die schwächere, aber wahre
     * Aussage — und der Hinweis, woran sie überprüfbar ist.
     */
    keinNetzOhneBeweis:
      'Auf diesem System lässt sich das nicht an einer Berechtigung ablesen. ' +
      'Nachprüfbar ist es am Quelltext: Die App enthält keinen Aufruf, der ' +
      'eine Verbindung herstellen würde.',
    keinePosition:
      'Die Position verlässt das Gerät nicht. Sie wird im Arbeitsspeicher ' +
      'ausgewertet und nicht dauerhaft gespeichert.',
    keinKonto:
      'Kein Konto, keine Anmeldung, keine Werbung, keine Analyse-Bibliothek, kein ' +
      'Absturzberichtsdienst.',
    lokaleDaten:
      'Auf dem Gerät bleiben nur die Einstellungen und das Fehlerprotokoll. ' +
      'Beides lässt sich in den Einstellungen löschen, spätestens mit der ' +
      'Deinstallation ist es weg.',
  },
} as const;

export type Strings = typeof STRINGS;

// --- Formatierer ----------------------------------------------------------
// Bewusst Funktionen statt Vorlagen mit Platzhaltern: Eine Vorlage
// "Blitzer in {0} Metern" lässt sich falsch befüllen, eine Signatur nicht.

/**
 * Entfernung als gesprochene Wortgruppe, etwa "in 300 Metern".
 *
 * Gerundet wird NICHT hier — die Rundungsstufen sind Verhalten und gehören
 * zum Audio-Modul, das die Schwellen aus config.ts zieht. Diese Funktion
 * formatiert, was sie bekommt.
 *
 * Kilometer kommen absichtlich nicht vor: Die Warndistanz liegt auch bei
 * höchster Einstellung unter 1100 m, und "in 1,1 Kilometern" ist für einen
 * Fahrer schwerer zu greifen als eine Meterzahl.
 */
export function entfernungAnsage(meter: number): string {
  const gerundet = Math.round(meter);
  // Die 1 ist Grammatik, keine Schwelle: "in 1 Metern" wäre falsch.
  const wort = gerundet === 1 ? STRINGS.ansage.meterSingular : STRINGS.ansage.meterPlural;
  return `${STRINGS.ansage.entfernungPraefix} ${gerundet} ${wort}`;
}

/** Entfernung als kurze Zahl für die Anzeige, etwa "300 m". */
export function entfernungAnzeige(meter: number): string {
  return `${Math.round(meter)} ${STRINGS.einheit.meter}`;
}

/**
 * Die vollständige Warnansage.
 *
 * Reihenfolge ist Absicht: erst was, dann wo, dann wie schnell. Wer nur den
 * Anfang mitbekommt, weiss immerhin, dass etwas kommt.
 *
 * `tempo === null` lässt die Tempoangabe weg, statt eine Null zu erfinden.
 * Bei rund 13 % der Anlagen ist das Limit unbekannt, in Bremen bei zwei
 * Dritteln.
 */
export function ansage(art: CameraKind, meter: number | null, tempo: number | null): string {
  const teile: string[] = [STRINGS.ansage.art[art]];
  teile.push(meter == null ? STRINGS.ansage.ohneEntfernung : entfernungAnsage(meter));
  if (tempo != null) teile.push(`${STRINGS.ansage.tempoPraefix} ${tempo}`);
  // Der Punkt am Ende ist für die Sprachausgabe, nicht für das Auge: ohne
  // Satzzeichen hängt die Stimme am Schluss in der Schwebe.
  return `${teile.join(', ')}.`;
}

/** "Stand der Daten: 29.07.2026" — Datum kommt fertig formatiert herein. */
export function datenstand(datum: string | null): string {
  if (datum == null) return STRINGS.daten.standUnbekannt;
  return `${STRINGS.daten.standPraefix}: ${datum}`;
}

/** Fussnote unter dem Rechtshinweis, Datum aus config.LAENDER_GATE.STAND. */
export function rechtsstand(datum: string): string {
  return `Rechtsstand: ${datum}`;
}

/** Statuszeile mit gerundeter Sekundenangabe, für den Watchdog. */
export function watchdogStatuszeile(sekunden: number): string {
  return `${STRINGS.watchdog.statuszeile} ${Math.round(sekunden)} s`;
}

/**
 * Banner-Text für ein Land, oder null, wenn dort keiner eingeblendet wird.
 * Bewusst als Abfrage statt als Wahrheitswert im UI-Code: Der Banner ist eine
 * rechtliche Anforderung und darf nicht an einer vergessenen if-Bedingung
 * hängen.
 */
export function bannerFuerLand(land: LandCode | null): { kurz: string; lang: string } | null {
  if (land === null) return null;
  // Aus der Gate-Tabelle abgeleitet, nicht danebengeschrieben: Wer dort
  // hinweisBanner setzt und hier keinen Text hinterlegt, bekommt null statt
  // eines stillschweigend fehlenden Banners — und der Test schlägt an.
  return Object.prototype.hasOwnProperty.call(BANNER, land)
    ? BANNER[land as BannerLand]
    : null;
}

/**
 * Braucht dieses Land einen dauerhaften Rechtshinweis?
 *
 * Einzige Quelle ist die Gate-Tabelle. Die frühere Fassung hatte die drei
 * Codes im UI-Code stehen, und `bannerFuerLand()` war dadurch toter Code — ein
 * neuer Eintrag mit hinweisBanner: true hätte nie einen Banner bekommen.
 */
export function brauchtBanner(land: LandCode | null): boolean {
  return land !== null && LAENDER_GATE.LAENDER[land].hinweisBanner;
}
