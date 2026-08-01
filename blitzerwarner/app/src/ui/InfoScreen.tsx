/**
 * Info — Attribution, Lizenz, Datenschutz und eine ehrliche Einordnung der
 * Datenqualität.
 *
 * Der Abschnitt über die eigenen Grenzen ist kein Kleingedrucktes, das man
 * wegräumt: Wer erwartet, vor mobilen Blitzern gewarnt zu werden, bekommt
 * sonst zu Recht einen Ein-Stern-Review. Lieber vorher enttäuschen als
 * nachher.
 */
import { Linking, Platform, Pressable, ScrollView, Share, StyleSheet, Text, View } from 'react-native';
import Constants from 'expo-constants';

import { STRINGS } from '../strings';
import {
  ABSTAND, GEWICHT, LINIE, RADIUS, SCHRIFT, SEITE, TOUCH, ZEILENHOEHE,
  gedrueckt, palette, spur, type ThemeMode,
} from './theme';
import { datasetOrNull } from '../core/dataset';
import { errorLog } from '../core/log';
import { useApp } from '../state/store';
import { fahrtprotokollAlsCsv, fahrtprotokollAnzahl } from '../location/task';

type Props = { mode: ThemeMode; onZurueck: () => void; onOeffneRechtliches: () => void };

export default function InfoScreen({ mode, onZurueck, onOeffneRechtliches }: Props) {
  const farben = palette(mode);
  const dataset = datasetOrNull();
  const fahrtprotokollAn = useApp((s) => s.settings.fahrtprotokoll);
  /*
   * Der Entzug der Internet-Berechtigung ist eine Android-Aussage.
   *
   * iOS kennt keine solche Berechtigung — jede App darf ins Netz, es gibt
   * nichts zu entziehen und nichts, was der Nutzer in den Systemeinstellungen
   * nachsehen könnte. Ohne die Plattformabfrage stand der Satz "In diesem
   * Build ist der App die Internet-Berechtigung entzogen … das lässt sich in
   * den App-Informationen des Systems nachsehen" auf jedem iPhone. Er war
   * dort in beiden Hälften falsch.
   *
   * Was auf iOS wahr bleibt, steht in keinNetzOhneBeweis: die App macht keine
   * Netzwerkaufrufe, nachprüfbar am Quelltext statt am System.
   */
  const internetEntzogen =
    Platform.OS === 'android' && Constants.expoConfig?.extra?.internetEntzogen === true;

  /**
   * Das Fahrtprotokoll ans System übergeben.
   *
   * Share und nicht Zwischenablage: Eine CSV mit mehreren tausend Zeilen in
   * die Zwischenablage zu legen ist auf beiden Systemen unzuverlässig, und
   * der Nutzer müsste sie danach irgendwo einfügen. Das Share-Sheet lässt ihn
   * ein Ziel wählen — Mail an sich selbst, Dateien, eine Tabelle.
   *
   * Die App verschickt dabei NICHTS von sich aus. Sie übergibt Text an das
   * System; wohin er geht, entscheidet der Nutzer. Das Produktversprechen
   * "keine Netzwerk-Requests zur Laufzeit" bleibt damit unangetastet.
   */
  function teileFahrtprotokoll(): void {
    try {
      const csv = fahrtprotokollAlsCsv();
      void Share.share({ message: csv, title: STRINGS.einstellungen.fahrtprotokollExport })
        .catch((err) => errorLog.error('start', 'Fahrtprotokoll konnte nicht geteilt werden', err));
    } catch (err) {
      errorLog.error('start', 'Fahrtprotokoll konnte nicht erzeugt werden', err);
    }
  }

  /**
   * Der einzige Ort in der App, an dem eine URL geöffnet wird — und das
   * überlässt die App dem Browser. Sie stellt selbst keine Verbindung her.
   */
  function oeffneLizenz(): void {
    Linking.openURL(dataset?.licenseUrl ?? STRINGS.daten.lizenzUrl).catch((err) =>
      errorLog.error('start', 'Lizenz-Link konnte nicht geöffnet werden', err));
  }

  return (
    <ScrollView
      style={{ backgroundColor: farben.hintergrund }}
      contentContainerStyle={stil.inhalt}
    >
      <Text style={[stil.titel, { color: farben.text }]}>
        {STRINGS.allgemein.appName}
      </Text>
      <Text style={[stil.text, { color: farben.textSekundaer }]}>
        {STRINGS.allgemein.appUntertitel}
      </Text>

      {/* Was die App nicht kann — ganz oben, nicht am Ende. */}
      <View style={[stil.karte, { borderColor: farben.warn, backgroundColor: farben.flaeche }]}>
        <Text style={[stil.kartenTitel, { color: farben.warn }]}>
          {STRINGS.onboarding.grenzenTitel}
        </Text>
        <Text style={[stil.text, { color: farben.textSekundaer }]}>
          {STRINGS.onboarding.grenzenText}
        </Text>
        <Text style={[stil.klein, { color: farben.textLeise }]}>
          {STRINGS.daten.qualitaetText}
        </Text>
      </View>

      {/* Datenquelle. Attribution ist Lizenzpflicht, kein Beiwerk. */}
      <View style={[stil.karte, { borderColor: farben.linie, backgroundColor: farben.flaeche }]}>
        <Text style={[stil.kartenTitel, { color: farben.text }]}>
          {STRINGS.daten.titel}
        </Text>
        <Text style={[stil.text, { color: farben.textSekundaer }]}>
          {STRINGS.daten.attribution}
        </Text>
        <Text style={[stil.text, { color: farben.textSekundaer }]}>
          {`Stand der Daten: ${(dataset?.osmTimestamp ?? '').slice(0, 10) || STRINGS.allgemein.unbekannt}` +
            (dataset ? ` · ${dataset.count} Anlagen` : '')}
        </Text>
        <Pressable
          onPress={oeffneLizenz}
          style={(z) => [stil.link, { borderColor: farben.linie }, gedrueckt(z)]}
          accessibilityRole="link"
          accessibilityLabel={STRINGS.daten.lizenzName}
        >
          <Text style={[stil.linkText, { color: farben.text }]}>
            {STRINGS.daten.lizenzName}
          </Text>
        </Pressable>
        <Text style={[stil.klein, { color: farben.textLeise }]}>
          {STRINGS.daten.lizenzText}
        </Text>
      </View>

      {/* Datenschutz — kurz, weil es wenig zu sagen gibt. */}
      <View style={[stil.karte, { borderColor: farben.linie, backgroundColor: farben.flaeche }]}>
        <Text style={[stil.kartenTitel, { color: farben.text }]}>
          {STRINGS.datenschutz.titel}
        </Text>
        <Text style={[stil.text, { color: farben.textSekundaer }]}>
          {STRINGS.datenschutz.kurz}
        </Text>
        <Text style={[stil.klein, { color: farben.textLeise }]}>
          {STRINGS.datenschutz.keinNetz}
        </Text>
        {/*
          Der starke Satz nur dort, wo er stimmt: Android, ausgelieferter
          Build. Im Entwicklungsbuild ist die Berechtigung da, weil der
          Dev-Client sein JS über das Netz lädt; auf iOS gibt es sie
          überhaupt nicht. In beiden Fällen steht der schwächere, aber wahre
          Satz da. Die App behauptet nicht, was sie nicht beweisen kann.
        */}
        {internetEntzogen ? (
          <>
            <Text style={[stil.klein, { color: farben.text }]}>
              {STRINGS.datenschutz.keinNetzBewiesen}
            </Text>
            <Text style={[stil.klein, { color: farben.textLeise }]}>
              {STRINGS.datenschutz.keinMikrofon}
            </Text>
          </>
        ) : (
          <Text style={[stil.klein, { color: farben.textLeise }]}>
            {STRINGS.datenschutz.keinNetzOhneBeweis}
          </Text>
        )}
      </View>

      {/* Rechtshinweis dauerhaft nachlesbar (Spec 2). */}
      <View style={[stil.karte, { borderColor: farben.linie, backgroundColor: farben.flaeche }]}>
        <Text style={[stil.kartenTitel, { color: farben.text }]}>
          {STRINGS.onboarding.rechtTitel}
        </Text>
        <Text style={[stil.klein, { color: farben.textSekundaer }]}>
          {STRINGS.onboarding.rechtNorm}
        </Text>
        <Text style={[stil.klein, { color: farben.textSekundaer }]}>
          {STRINGS.onboarding.rechtBeifahrer}
        </Text>
        <Text style={[stil.klein, { color: farben.textLeise }]}>
          {STRINGS.onboarding.rechtKeineBeratung}
        </Text>
      </View>

      {/*
        Nur sichtbar, wenn der Fahrtenschreiber eingeschaltet ist. Ein Knopf,
        der ein leeres Protokoll teilt, wäre genau die Sorte UI-Element, die
        eine Funktion behauptet, die gerade nicht läuft.
      */}
      {fahrtprotokollAn && (
        <View style={[stil.karte, { borderColor: farben.linie, backgroundColor: farben.flaeche }]}>
          <Text style={[stil.kartenTitel, { color: farben.text }]}>
            {STRINGS.einstellungen.feld.fahrtprotokoll.titel}
          </Text>
          <Text style={[stil.klein, { color: farben.textSekundaer }]}>
            {STRINGS.einstellungen.fahrtprotokollHilfe}
          </Text>
          <Text style={[stil.klein, { color: farben.textLeise }]}>
            {STRINGS.einstellungen.fahrtprotokollAkkuHinweis}
          </Text>
          <Pressable
            onPress={teileFahrtprotokoll}
            disabled={fahrtprotokollAnzahl() === 0}
            style={(z) => [
              stil.link, { borderColor: farben.linie },
              gedrueckt(z, fahrtprotokollAnzahl() === 0),
            ]}
            accessibilityRole="button"
            accessibilityLabel={STRINGS.einstellungen.fahrtprotokollExport}
          >
            <Text style={[stil.linkText, { color: farben.text }]}>
              {fahrtprotokollAnzahl() === 0
                ? STRINGS.einstellungen.fahrtprotokollLeer
                : `${STRINGS.einstellungen.fahrtprotokollExport} (${fahrtprotokollAnzahl()})`}
            </Text>
          </Pressable>
        </View>
      )}

      {/*
        Der Weg zu den Rechtsdokumenten. Er steht hier und nicht versteckt in
        den Einstellungen, weil ein Store-Prüfer, der die
        Datenschutzerklärung sucht und nicht findet, ablehnt.
      */}
      <Pressable
        onPress={onOeffneRechtliches}
        style={(z) => [stil.link, { borderColor: farben.linie }, gedrueckt(z)]}
        accessibilityRole="button"
        accessibilityLabel={STRINGS.rechtliches.titel}
      >
        <Text style={[stil.linkText, { color: farben.text }]}>
          {STRINGS.rechtliches.titel}
        </Text>
      </Pressable>

      <Pressable
        onPress={onZurueck}
        style={(z) => [stil.knopf, { borderColor: farben.linie }, gedrueckt(z)]}
        accessibilityRole="button"
        accessibilityLabel={STRINGS.allgemein.zurueck}
      >
        <Text style={[stil.knopfText, { color: farben.text }]}>
          {STRINGS.allgemein.zurueck}
        </Text>
      </Pressable>
    </ScrollView>
  );
}

const stil = StyleSheet.create({
  inhalt: { padding: ABSTAND.RAND, paddingTop: SEITE.OBEN, gap: ABSTAND.L, paddingBottom: SEITE.UNTEN },
  titel: { fontSize: SCHRIFT.WARN_TITEL, letterSpacing: spur(SCHRIFT.WARN_TITEL), lineHeight: SCHRIFT.WARN_TITEL * ZEILENHOEHE.ENG, fontWeight: GEWICHT.FETT },
  karte: { borderWidth: LINIE.DUENN, borderRadius: RADIUS.M, padding: ABSTAND.L, gap: ABSTAND.M },
  kartenTitel: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.FETT },
  text: { fontSize: SCHRIFT.TEXT, lineHeight: SCHRIFT.TEXT * ZEILENHOEHE.TEXT },
  klein: { fontSize: SCHRIFT.KLEIN, lineHeight: SCHRIFT.KLEIN * ZEILENHOEHE.TEXT },
  link: {
    minHeight: TOUCH.MIN, borderWidth: LINIE.DUENN, borderRadius: RADIUS.S,
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: ABSTAND.M,
  },
  linkText: { fontSize: SCHRIFT.TEXT, textDecorationLine: 'underline' },
  knopf: {
    marginTop: ABSTAND.M, minHeight: TOUCH.MIN, borderWidth: LINIE.DUENN, borderRadius: RADIUS.M,
    alignItems: 'center', justifyContent: 'center',
  },
  knopfText: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.MITTEL },
});
