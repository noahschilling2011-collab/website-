/**
 * Der Fahrt-Screen.
 *
 * Der einzige Screen, der während der Fahrt sichtbar ist — und das meist nur
 * für den Bruchteil einer Sekunde im Vorbeischauen. Jede Entscheidung hier
 * folgt daraus:
 *
 *  - Echtes Schwarz, keine Transparenzen, kein Blur. Blur kostet GPU-Zeit
 *    und damit Akku und verschlechtert bei Sonnenlicht die Lesbarkeit.
 *  - Genau eine Akzentfarbe. Alles andere Graustufen.
 *  - Keine Animation ausser einem langsamen Puls am Aktiv-Indikator.
 *    Bewegung im Sichtfeld beim Fahren ist ein Ablenkungsrisiko.
 *  - Der Tacho mit festen Ziffernbreiten, sonst springt die Zahl und das
 *    Auge folgt der Bewegung statt den Wert abzulesen.
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  AccessibilityInfo, Animated, Pressable, ScrollView, StyleSheet, Text, View,
} from 'react-native';

import { STRINGS } from '../strings';
import { GEWICHT, SCHRIFT, TOUCH, ZIFFERN_FEST, palette, type ThemeMode } from './theme';
import { useApp } from '../state/store';
import {
  laeuftTracking, landStatus, letzterFix, starteTracking, stoppeTracking, watchdogState,
} from '../location/task';
import { pruefe, statuszeile } from '../location/watchdog';
import { warneSystem } from '../audio/player';
import { datasetOrNull } from '../core/dataset';
import { distanceToNearest } from '../core/warn';
import { createSpeedState, readSpeed, updateSpeed } from '../core/speed';
import { errorLog } from '../core/log';

type Props = {
  mode: ThemeMode;
  onOeffneEinstellungen: () => void;
  onOeffneInfo: () => void;
};

const AKTUALISIERUNG_MS = 1000;

export default function DriveScreen({ mode, onOeffneEinstellungen, onOeffneInfo }: Props) {
  const farben = palette(mode);
  const settings = useApp((s) => s.settings);

  const [aktiv, setAktiv] = useState(false);
  const [tempoKmh, setTempoKmh] = useState<number | null>(null);
  const [tempoUnsicher, setTempoUnsicher] = useState(false);
  const [naechsteM, setNaechsteM] = useState<number | null>(null);
  const [watchdogTot, setWatchdogTot] = useState(false);
  const [status, setStatus] = useState<{ seitMin: number | null; fixVorSek: number | null }>({
    seitMin: null, fixVorSek: null,
  });

  const tacho = useRef(createSpeedState());
  const letzteFixZeit = useRef<number | null>(null);
  const puls = useRef(new Animated.Value(1)).current;
  const [reduzierteBewegung, setReduzierteBewegung] = useState(false);

  const dataset = datasetOrNull();
  const [land, setLand] = useState<string | null>(null);

  // Systemeinstellung "Bewegung reduzieren" respektieren.
  useEffect(() => {
    let abgebrochen = false;
    AccessibilityInfo.isReduceMotionEnabled()
      .then((an) => { if (!abgebrochen) setReduzierteBewegung(an); })
      .catch((err) => errorLog.error('start', 'Bewegungseinstellung nicht lesbar', err));
    return () => { abgebrochen = true; };
  }, []);

  useEffect(() => {
    laeuftTracking().then(setAktiv).catch((err) =>
      errorLog.error('hintergrund', 'Trackingstatus nicht lesbar', err));
  }, []);

  /** Der langsame Puls — das einzige bewegte Element. */
  useEffect(() => {
    if (!aktiv || reduzierteBewegung) {
      puls.setValue(1);
      return;
    }
    const schleife = Animated.loop(
      Animated.sequence([
        Animated.timing(puls, { toValue: 0.35, duration: 1200, useNativeDriver: true }),
        Animated.timing(puls, { toValue: 1, duration: 1200, useNativeDriver: true }),
      ]),
    );
    schleife.start();
    return () => schleife.stop();
  }, [aktiv, reduzierteBewegung, puls]);

  /**
   * Anzeige aus dem Task-Zustand nachziehen.
   *
   * Der Task läuft in einem eigenen JS-Kontext; er kann React nicht direkt
   * aktualisieren. Deshalb wird hier gepollt — einmal pro Sekunde, was für
   * eine Anzeige reicht und praktisch keinen Strom kostet, weil der Screen
   * ohnehin nur an ist, wenn jemand hinschaut.
   */
  useEffect(() => {
    const timer = setInterval(() => {
      const fix = letzterFix();
      const jetzt = Date.now();

      if (fix) {
        // updateSpeed liefert die Anzeige gleich mit; readSpeed nur, wenn
        // kein neuer Fix da ist und der Haltezeitraum ablaufen soll.
        const anzeige = fix.t !== letzteFixZeit.current
          ? updateSpeed(tacho.current, fix, settings)
          : readSpeed(tacho.current, jetzt, settings);
        letzteFixZeit.current = fix.t;
        setTempoKmh(anzeige.kmh);
        setTempoUnsicher(anzeige.quality === 'unsicher' || anzeige.gehalten);

        if (dataset) setNaechsteM(distanceToNearest(fix, dataset.grid));
      }

      setLand(landStatus().umriss);

      const wd = watchdogState();
      const s = statuszeile(wd, jetzt);
      setStatus({ seitMin: s.aktivSeitMin, fixVorSek: s.letzterFixVorSek });

      const { alarmAusloesen, status: wdStatus } = pruefe(wd, jetzt);
      setWatchdogTot(wdStatus === 'tot');
      if (alarmAusloesen) {
        // Hörbar, nicht stumm im Log: Ein stiller Ausfall ist der
        // gefährlichste Zustand der App.
        void warneSystem(STRINGS.watchdog.ansage);
      }
    }, AKTUALISIERUNG_MS);
    return () => clearInterval(timer);
  }, [dataset, settings]);

  const umschalten = useCallback(async () => {
    if (aktiv) {
      await stoppeTracking();
      setAktiv(false);
      tacho.current = createSpeedState();
      letzteFixZeit.current = null;
      setTempoKmh(null);
    } else {
      const ok = await starteTracking(settings);
      setAktiv(ok);
    }
  }, [aktiv, settings]);

  const bannerLand = land === 'DE' || land === 'AT' || land === 'CH' ? land : null;

  return (
    <View style={[stil.wurzel, { backgroundColor: farben.hintergrund }]}>
      <ScrollView contentContainerStyle={stil.inhalt}>

        {/* Rechtshinweis-Banner. Nicht abschaltbar (Spec 2). */}
        {bannerLand != null && (
          <View
            style={[stil.banner, { borderColor: farben.warn, backgroundColor: farben.warnGedaempft }]}
            accessibilityRole="alert"
          >
            <Text style={[stil.bannerText, { color: farben.text }]}>
              {STRINGS.banner[bannerLand].kurz}
            </Text>
          </View>
        )}

        {/* Watchdog-Warnung. Rot PLUS Text PLUS Ton — nie nur Farbe. */}
        {watchdogTot && (
          <View
            style={[stil.banner, { borderColor: farben.warn, backgroundColor: farben.warnGedaempft }]}
            accessibilityRole="alert"
          >
            <Text style={[stil.bannerTitel, { color: farben.warn }]}>
              {STRINGS.watchdog.titel}
            </Text>
            <Text style={[stil.bannerText, { color: farben.textSekundaer }]}>
              {STRINGS.watchdog.handlung}
            </Text>
          </View>
        )}

        {/* Tacho */}
        <View style={stil.tachoBlock} accessible accessibilityLabel={
          tempoKmh == null
            ? STRINGS.fahrt.status.sucheGps
            : `${tempoKmh} ${STRINGS.fahrt.tachoEinheit}`
        }>
          <Text
            style={[
              stil.tacho,
              ZIFFERN_FEST,
              { color: tempoUnsicher ? farben.textInaktiv : farben.text },
            ]}
            // Der Tacho darf nicht mitwachsen, sonst bricht das Layout bei
            // 200 % Systemschriftgrösse.
            allowFontScaling={false}
          >
            {tempoKmh ?? STRINGS.fahrt.tachoUnbekannt}
          </Text>
          <Text style={[stil.tachoEinheit, { color: farben.textLeise }]}>
            {STRINGS.fahrt.tachoEinheit}
            {tempoUnsicher ? ` · ${STRINGS.fahrt.status.gpsSchwach}` : ''}
          </Text>
        </View>

        {/* Nächste Anlage */}
        <View style={stil.anlageBlock}>
          <Text style={[stil.label, { color: farben.textLeise }]}>
            {STRINGS.fahrt.naechsteAnlage}
          </Text>
          <Text style={[stil.entfernung, ZIFFERN_FEST, { color: farben.text }]}>
            {naechsteM == null
              ? STRINGS.fahrt.keineAnlageInDerNaehe
              : `${Math.round(naechsteM)} m`}
          </Text>
        </View>

        {/* Statuszeile: der Nutzer muss sehen, dass die App wirklich läuft. */}
        <View style={stil.statusZeile}>
          <Animated.View
            style={[
              stil.punkt,
              { backgroundColor: aktiv ? farben.warn : farben.textInaktiv, opacity: aktiv ? puls : 1 },
            ]}
          />
          <Text style={[stil.status, { color: farben.textSekundaer }]}>
            {!aktiv
              ? STRINGS.fahrt.status.inaktiv
              : `${STRINGS.fahrt.status.aktiv}` +
                (status.seitMin != null ? ` · seit ${status.seitMin} min` : '') +
                (status.fixVorSek != null ? ` · Position vor ${status.fixVorSek} s` : ` · ${STRINGS.fahrt.status.sucheGps}`)}
          </Text>
        </View>

        {/* Datenlücke ist ein gestalteter Zustand, kein leerer Bildschirm. */}
        {dataset == null && (
          <View style={[stil.leer, { borderColor: farben.linie }]}>
            <Text style={[stil.bannerTitel, { color: farben.text }]}>
              {STRINGS.leer.keineDatenRegionTitel}
            </Text>
            <Text style={[stil.bannerText, { color: farben.textSekundaer }]}>
              {STRINGS.leer.keineDatenRegionText}
            </Text>
          </View>
        )}
      </ScrollView>

      {/* Start/Stop — grosses Ziel, im Auto bedienbar. */}
      <Pressable
        onPress={umschalten}
        style={({ pressed }) => [
          stil.knopf,
          {
            backgroundColor: aktiv ? farben.warnGedaempft : farben.warn,
            borderColor: farben.warn,
            opacity: pressed ? 0.8 : 1,
          },
        ]}
        accessibilityRole="button"
        accessibilityLabel={aktiv ? STRINGS.fahrt.fahrtBeenden : STRINGS.fahrt.fahrtStarten}
      >
        <Text style={[stil.knopfText, { color: aktiv ? farben.text : farben.aufWarn }]}>
          {aktiv ? STRINGS.fahrt.fahrtBeenden : STRINGS.fahrt.fahrtStarten}
        </Text>
      </Pressable>

      <View style={stil.fussZeile}>
        <Pressable
          onPress={onOeffneEinstellungen}
          style={stil.fussKnopf}
          accessibilityRole="button"
          accessibilityLabel={STRINGS.einstellungen.titel}
        >
          <Text style={[stil.fussText, { color: farben.textSekundaer }]}>
            {STRINGS.einstellungen.titel}
          </Text>
        </Pressable>
        <Pressable
          onPress={onOeffneInfo}
          style={stil.fussKnopf}
          accessibilityRole="button"
          accessibilityLabel={STRINGS.daten.titel}
        >
          <Text style={[stil.fussText, { color: farben.textSekundaer }]}>
            {STRINGS.daten.titel}
          </Text>
        </Pressable>
      </View>
    </View>
  );
}

const stil = StyleSheet.create({
  wurzel: { flex: 1 },
  inhalt: { padding: 20, paddingTop: 48, gap: 28 },
  banner: { borderWidth: 1, borderRadius: 8, padding: 14, gap: 6 },
  bannerTitel: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.FETT },
  bannerText: { fontSize: SCHRIFT.KLEIN, lineHeight: SCHRIFT.KLEIN * 1.45 },
  tachoBlock: { alignItems: 'center', gap: 2 },
  tacho: { fontSize: SCHRIFT.TACHO, fontWeight: GEWICHT.FETT, lineHeight: SCHRIFT.TACHO * 1.05 },
  tachoEinheit: { fontSize: SCHRIFT.TACHO_EINHEIT },
  anlageBlock: { alignItems: 'center', gap: 4 },
  label: { fontSize: SCHRIFT.LABEL, textTransform: 'uppercase', letterSpacing: 1 },
  entfernung: { fontSize: SCHRIFT.WARN_ENTFERNUNG, fontWeight: GEWICHT.MITTEL },
  statusZeile: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8 },
  punkt: { width: 10, height: 10, borderRadius: 5 },
  status: { fontSize: SCHRIFT.STATUS },
  leer: { borderWidth: 1, borderRadius: 8, padding: 16, gap: 8 },
  knopf: {
    marginHorizontal: 20, marginBottom: 12, minHeight: TOUCH.MIN,
    borderWidth: 2, borderRadius: 12, alignItems: 'center', justifyContent: 'center',
  },
  knopfText: { fontSize: SCHRIFT.WARN_TITEL, fontWeight: GEWICHT.FETT },
  fussZeile: { flexDirection: 'row', justifyContent: 'space-around', paddingBottom: 24 },
  fussKnopf: { minHeight: TOUCH.MIN, minWidth: TOUCH.MIN, justifyContent: 'center', paddingHorizontal: 20 },
  fussText: { fontSize: SCHRIFT.TEXT },
});
