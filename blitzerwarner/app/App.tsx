/**
 * Wurzelkomponente.
 *
 * Kein Navigations-Framework: Bei vier Screens, von denen einer während der
 * Fahrt läuft und drei im Stand gelesen werden, wäre ein Navigator mehr
 * Abhängigkeit als Nutzen. Ein Zustandswert genügt.
 */
import { useEffect, useMemo, useState } from 'react';
import { StatusBar, StyleSheet, Text, View } from 'react-native';

import { STRINGS } from './src/strings';
import { palette, type ThemeMode } from './src/ui/theme';
import { useApp } from './src/state/store';
import { loadDataset } from './src/core/dataset';
import { errorLog } from './src/core/log';
import { initAudio } from './src/audio/player';
import { istNacht } from './src/core/daylight';
import { letzterFix } from './src/location/task';
import DriveScreen from './src/ui/DriveScreen';
import OnboardingScreen from './src/ui/OnboardingScreen';
import SettingsScreen from './src/ui/SettingsScreen';
import InfoScreen from './src/ui/InfoScreen';

type Ansicht = 'fahrt' | 'einstellungen' | 'info';

export default function App() {
  const geladen = useApp((s) => s.geladen);
  const bestaetigt = useApp((s) => s.rechtshinweisBestaetigt);
  const ladeAlles = useApp((s) => s.ladeAlles);

  const [ansicht, setAnsicht] = useState<Ansicht>('fahrt');
  const [datensatzFehler, setDatensatzFehler] = useState(false);
  const [jetzt, setJetzt] = useState(() => Date.now());

  /**
   * Start: Datensatz laden, Audio-Session aufsetzen, Einstellungen lesen.
   *
   * Der Datensatz wird EINMAL geparst — 5053 Anlagen, rund 360 KB. Das im
   * Hintergrund-Task pro Positionsupdate zu tun wäre der sicherste Weg, das
   * Akkuziel zu verfehlen.
   */
  useEffect(() => {
    try {
      loadDataset();
    } catch (err) {
      // Ohne Daten kann die App nicht warnen. Das muss sichtbar sein und
      // nicht in einem leeren Bildschirm enden.
      setDatensatzFehler(true);
      errorLog.error('daten', 'Datensatz konnte nicht geladen werden', err);
    }

    void initAudio();
    void ladeAlles();
  }, [ladeAlles]);

  /**
   * Nachtmodus, offline aus Position und Datum gerechnet.
   *
   * Einmal pro Viertelstunde prüfen genügt — der Sonnenstand ändert sich
   * nicht schneller, und ein häufigerer Timer würde nur Strom kosten.
   */
  useEffect(() => {
    const timer = setInterval(() => setJetzt(Date.now()), 15 * 60 * 1000);
    return () => clearInterval(timer);
  }, []);

  const mode: ThemeMode = useMemo(() => {
    const fix = letzterFix();
    if (!fix) return 'tag';
    try {
      return istNacht(fix.lat, fix.lon, new Date(jetzt)) ? 'nacht' : 'tag';
    } catch (err) {
      errorLog.error('start', 'Nachtmodus konnte nicht bestimmt werden', err);
      return 'tag';
    }
  }, [jetzt]);

  const farben = palette(mode);

  if (!geladen) {
    return (
      <View style={[stil.mitte, { backgroundColor: farben.hintergrund }]}>
        <StatusBar barStyle="light-content" backgroundColor={farben.hintergrund} />
        <Text style={[stil.text, { color: farben.textSekundaer }]}>
          {STRINGS.allgemein.appName}
        </Text>
      </View>
    );
  }

  if (datensatzFehler) {
    return (
      <View style={[stil.mitte, { backgroundColor: farben.hintergrund }]}>
        <StatusBar barStyle="light-content" backgroundColor={farben.hintergrund} />
        <Text style={[stil.titel, { color: farben.warn }]}>
          {STRINGS.fehler.datensatzUnlesbar.titel}
        </Text>
        <Text style={[stil.text, { color: farben.textSekundaer }]}>
          {STRINGS.fehler.datensatzUnlesbar.handlung}
        </Text>
      </View>
    );
  }

  if (!bestaetigt) {
    return (
      <>
        <StatusBar barStyle="light-content" backgroundColor={farben.hintergrund} />
        <OnboardingScreen mode={mode} />
      </>
    );
  }

  return (
    <>
      <StatusBar barStyle="light-content" backgroundColor={farben.hintergrund} />
      {ansicht === 'fahrt' && (
        <DriveScreen
          mode={mode}
          onOeffneEinstellungen={() => setAnsicht('einstellungen')}
          onOeffneInfo={() => setAnsicht('info')}
        />
      )}
      {ansicht === 'einstellungen' && (
        <SettingsScreen mode={mode} onZurueck={() => setAnsicht('fahrt')} />
      )}
      {ansicht === 'info' && (
        <InfoScreen mode={mode} onZurueck={() => setAnsicht('fahrt')} />
      )}
    </>
  );
}

const stil = StyleSheet.create({
  mitte: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12, padding: 24 },
  titel: { fontSize: 24, fontWeight: '700', textAlign: 'center' },
  text: { fontSize: 18, textAlign: 'center', lineHeight: 26 },
});
