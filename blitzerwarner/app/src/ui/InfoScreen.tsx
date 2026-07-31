/**
 * Info — Attribution, Lizenz, Datenschutz und eine ehrliche Einordnung der
 * Datenqualität.
 *
 * Der Abschnitt über die eigenen Grenzen ist kein Kleingedrucktes, das man
 * wegräumt: Wer erwartet, vor mobilen Blitzern gewarnt zu werden, bekommt
 * sonst zu Recht einen Ein-Stern-Review. Lieber vorher enttäuschen als
 * nachher.
 */
import { Linking, Pressable, ScrollView, Share, StyleSheet, Text, View } from 'react-native';
import Constants from 'expo-constants';

import { STRINGS } from '../strings';
import { GEWICHT, SCHRIFT, TOUCH, palette, type ThemeMode } from './theme';
import { datasetOrNull } from '../core/dataset';
import { errorLog } from '../core/log';
import { useApp } from '../state/store';
import { fahrtprotokollAlsCsv, fahrtprotokollAnzahl } from '../location/task';

type Props = { mode: ThemeMode; onZurueck: () => void };

export default function InfoScreen({ mode, onZurueck }: Props) {
  const farben = palette(mode);
  const dataset = datasetOrNull();
  const fahrtprotokollAn = useApp((s) => s.settings.fahrtprotokoll);
  const internetEntzogen = Constants.expoConfig?.extra?.internetEntzogen === true;

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
          style={[stil.link, { borderColor: farben.linie }]}
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
          Nur im ausgelieferten Build. Im Entwicklungsbuild ist die
          Berechtigung da, weil der Dev-Client sein JS über das Netz lädt —
          dann wäre der Satz falsch, und die App behauptet nicht, was sie
          nicht beweisen kann. Die Angabe kommt aus app.config.js.
        */}
        {internetEntzogen && (
          <>
            <Text style={[stil.klein, { color: farben.text }]}>
              {STRINGS.datenschutz.keinNetzBewiesen}
            </Text>
            <Text style={[stil.klein, { color: farben.textLeise }]}>
              {STRINGS.datenschutz.keinMikrofon}
            </Text>
          </>
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
            style={[stil.link, { borderColor: farben.linie }]}
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

      <Pressable
        onPress={onZurueck}
        style={[stil.knopf, { borderColor: farben.linie }]}
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
  inhalt: { padding: 20, paddingTop: 56, gap: 16, paddingBottom: 40 },
  titel: { fontSize: SCHRIFT.WARN_TITEL, fontWeight: GEWICHT.FETT },
  karte: { borderWidth: 1, borderRadius: 12, padding: 16, gap: 10 },
  kartenTitel: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.FETT },
  text: { fontSize: SCHRIFT.TEXT, lineHeight: SCHRIFT.TEXT * 1.45 },
  klein: { fontSize: SCHRIFT.KLEIN, lineHeight: SCHRIFT.KLEIN * 1.45 },
  link: {
    minHeight: TOUCH.MIN, borderWidth: 1, borderRadius: 8,
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: 12,
  },
  linkText: { fontSize: SCHRIFT.TEXT, textDecorationLine: 'underline' },
  knopf: {
    marginTop: 12, minHeight: TOUCH.MIN, borderWidth: 1, borderRadius: 12,
    alignItems: 'center', justifyContent: 'center',
  },
  knopfText: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.MITTEL },
});
