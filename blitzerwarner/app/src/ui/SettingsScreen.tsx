/**
 * Einstellungen.
 *
 * Wird im Stand gelesen, nicht während der Fahrt — hier darf der Text kleiner
 * sein und es darf gescrollt werden. Die Touch-Ziele bleiben trotzdem gross,
 * weil auch dieser Screen im Auto bedient wird.
 */
import { Pressable, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';

import { STRINGS } from '../strings';
import { GEWICHT, SCHRIFT, TOUCH, palette, type ThemeMode } from './theme';
import { useApp } from '../state/store';
import { datasetOrNull } from '../core/dataset';
import { errorLog } from '../core/log';
import { DATENQUALITAET } from '../core/country-data';
import type { Settings } from '../types';

type Props = { mode: ThemeMode; onZurueck: () => void; onOeffneRechtliches: () => void };

const FAKTOR_STUFEN = [0.75, 1, 1.25, 1.5, 2] as const;

export default function SettingsScreen({ mode, onZurueck, onOeffneRechtliches }: Props) {
  const farben = palette(mode);
  const settings = useApp((s) => s.settings);
  const setze = useApp((s) => s.setzeEinstellung);
  const dataset = datasetOrNull();

  const schalter = (
    key: keyof Pick<
      Settings,
      'sprachansage' | 'rotlichtblitzer' | 'motorradModus' | 'haptik' | 'fahrtprotokoll'
    >,
    text: { titel: string; hilfe?: string },
  ) => (
    <View style={[stil.zeile, { borderColor: farben.linie }]}>
      <View style={stil.zeileText}>
        <Text style={[stil.label, { color: farben.text }]}>{text.titel}</Text>
        {text.hilfe && (
          <Text style={[stil.hilfe, { color: farben.textLeise }]}>{text.hilfe}</Text>
        )}
      </View>
      <Switch
        value={settings[key]}
        onValueChange={(v) => void setze(key, v)}
        trackColor={{ false: farben.linie, true: farben.warn }}
        accessibilityLabel={text.titel}
      />
    </View>
  );

  return (
    <ScrollView
      style={{ backgroundColor: farben.hintergrund }}
      contentContainerStyle={stil.inhalt}
    >
      <Text style={[stil.titel, { color: farben.text }]}>
        {STRINGS.einstellungen.titel}
      </Text>

      {/* Warnung */}
      <Text style={[stil.abschnitt, { color: farben.textLeise }]}>
        {STRINGS.einstellungen.abschnittWarnung}
      </Text>

      <View style={[stil.zeile, { borderColor: farben.linie }]}>
        <View style={stil.zeileText}>
          <Text style={[stil.label, { color: farben.text }]}>
            {STRINGS.einstellungen.feld.warnDistanceFactor.titel}
          </Text>
          <Text style={[stil.hilfe, { color: farben.textLeise }]}>
            {STRINGS.einstellungen.feld.warnDistanceFactor.hilfe}
          </Text>
        </View>
      </View>
      <View style={stil.stufen}>
        {FAKTOR_STUFEN.map((f) => {
          const aktiv = Math.abs(settings.warnDistanceFactor - f) < 0.01;
          return (
            <Pressable
              key={f}
              onPress={() => void setze('warnDistanceFactor', f)}
              style={[
                stil.stufe,
                {
                  borderColor: aktiv ? farben.warn : farben.linie,
                  backgroundColor: aktiv ? farben.warnGedaempft : 'transparent',
                },
              ]}
              accessibilityRole="button"
              accessibilityState={{ selected: aktiv }}
              accessibilityLabel={`Warndistanz Faktor ${f}`}
            >
              <Text style={[stil.stufeText, { color: aktiv ? farben.warn : farben.textSekundaer }]}>
                {`${f}×`}
              </Text>
            </Pressable>
          );
        })}
      </View>

      {schalter('rotlichtblitzer', STRINGS.einstellungen.feld.rotlichtblitzer)}

      {/* Ausgabe */}
      <Text style={[stil.abschnitt, { color: farben.textLeise }]}>
        {STRINGS.einstellungen.abschnittAusgabe}
      </Text>
      {schalter('sprachansage', STRINGS.einstellungen.feld.sprachansage)}
      {schalter('motorradModus', STRINGS.einstellungen.feld.motorradModus)}
      {schalter('haptik', STRINGS.einstellungen.feld.haptik)}

      {/* Daten */}
      <Text style={[stil.abschnitt, { color: farben.textLeise }]}>
        {STRINGS.einstellungen.abschnittDaten}
      </Text>
      <View style={[stil.karte, { borderColor: farben.linie, backgroundColor: farben.flaeche }]}>
        <Text style={[stil.label, { color: farben.text }]}>
          {dataset
            ? `${dataset.count} Anlagen`
            : STRINGS.fehler.datensatzUnlesbar.titel}
        </Text>
        <Text style={[stil.hilfe, { color: farben.textSekundaer }]}>
          {`Stand der Daten: ${(dataset?.osmTimestamp ?? '').slice(0, 10) || STRINGS.allgemein.unbekannt}`}
        </Text>
        <Text style={[stil.hilfe, { color: farben.textLeise }]}>
          {STRINGS.daten.attribution} · {STRINGS.daten.lizenzName}
        </Text>
      </View>

      {/*
        Ehrlichkeit über die eigene Datenlage. Die Landesumrisse für das
        Gate sind derzeit grob — das darf der Nutzer wissen, weil davon
        abhängt, ob die Warnung im richtigen Land läuft.
      */}
      {DATENQUALITAET !== 'geprüft' && (
        <View style={[stil.karte, { borderColor: farben.warn, backgroundColor: farben.warnGedaempft }]}>
          <Text style={[stil.label, { color: farben.warn }]}>Landeserkennung vorläufig</Text>
          <Text style={[stil.hilfe, { color: farben.textSekundaer }]}>
            {`Die Landesumrisse sind als "${DATENQUALITAET}" hinterlegt. In Grenznähe ` +
             'kann die Zuordnung falsch sein. Im Zweifel bleibt die Warnung aus.'}
          </Text>
        </View>
      )}

      {/* Recht und Lizenz */}
      <Text style={[stil.abschnitt, { color: farben.textLeise }]}>
        {STRINGS.einstellungen.abschnittRecht}
      </Text>
      <Pressable
        onPress={onOeffneRechtliches}
        style={[stil.zeile, { borderColor: farben.linie }]}
        accessibilityRole="button"
        accessibilityLabel={STRINGS.rechtliches.titel}
      >
        <View style={stil.zeileText}>
          <Text style={[stil.label, { color: farben.text }]}>
            {STRINGS.rechtliches.titel}
          </Text>
          <Text style={[stil.hilfe, { color: farben.textLeise }]}>
            {STRINGS.rechtliches.meineDatenHilfe}
          </Text>
        </View>
      </Pressable>

      {/* Diagnose */}
      <Text style={[stil.abschnitt, { color: farben.textLeise }]}>
        {STRINGS.einstellungen.abschnittDiagnose}
      </Text>
      {/*
        Der Fahrtenschreiber steht in der Diagnose und nicht bei der Warnung:
        Er ist kein Fahrkomfort, sondern ein Messwerkzeug. Standardmässig aus,
        weil hier als einzigem Ort der App eine vollständige Bewegungsspur
        entsteht.
      */}
      {schalter('fahrtprotokoll', STRINGS.einstellungen.feld.fahrtprotokoll)}
      {settings.fahrtprotokoll && (
        <Text style={[stil.hilfe, { color: farben.textLeise }]}>
          {STRINGS.einstellungen.fahrtprotokollVerweis}
        </Text>
      )}

      <View style={[stil.karte, { borderColor: farben.linie, backgroundColor: farben.flaeche }]}>
        <Text style={[stil.label, { color: farben.text }]}>
          {STRINGS.einstellungen.fehlerprotokoll}
        </Text>
        <Text style={[stil.hilfe, { color: farben.textLeise }]}>
          {STRINGS.einstellungen.fehlerprotokollHilfe}
        </Text>
        <Text style={[stil.protokoll, { color: farben.textSekundaer }]} selectable>
          {errorLog.entries().slice(-12).map((e) =>
            `${new Date(e.t).toISOString().slice(11, 19)} ${e.level} ${e.area}: ${e.message}`,
          ).join('\n') || '—'}
        </Text>
      </View>

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
  inhalt: { padding: 20, paddingTop: 56, gap: 12, paddingBottom: 40 },
  titel: { fontSize: SCHRIFT.WARN_TITEL, fontWeight: GEWICHT.FETT, marginBottom: 8 },
  abschnitt: {
    fontSize: SCHRIFT.LABEL, textTransform: 'uppercase', letterSpacing: 1, marginTop: 20,
  },
  zeile: {
    flexDirection: 'row', alignItems: 'center', gap: 16,
    minHeight: TOUCH.MIN, borderBottomWidth: 1, paddingVertical: 8,
  },
  zeileText: { flex: 1, gap: 2 },
  label: { fontSize: SCHRIFT.TEXT },
  hilfe: { fontSize: SCHRIFT.KLEIN, lineHeight: SCHRIFT.KLEIN * 1.4 },
  stufen: { flexDirection: 'row', gap: 8 },
  stufe: {
    flex: 1, minHeight: TOUCH.MIN, borderWidth: 1, borderRadius: 8,
    alignItems: 'center', justifyContent: 'center',
  },
  stufeText: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.MITTEL },
  karte: { borderWidth: 1, borderRadius: 12, padding: 16, gap: 8 },
  protokoll: { fontSize: SCHRIFT.KLEIN, fontFamily: 'monospace' },
  knopf: {
    marginTop: 24, minHeight: TOUCH.MIN, borderWidth: 1, borderRadius: 12,
    alignItems: 'center', justifyContent: 'center',
  },
  knopfText: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.MITTEL },
});
