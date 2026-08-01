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

import { STRINGS, bannerFuerLand } from '../strings';
import {
  ABSTAND, DAUER, DECKKRAFT, GEWICHT, LINIE, MASS, RADIUS, SCHRIFT, SEITE, SPUR,
  TOUCH, ZEILENHOEHE, ZIFFERN_FEST, gedrueckt, palette, spur, type ThemeMode,
} from './theme';
import { useApp } from '../state/store';
import {
  laeuftTracking, landStatus, letzterFix, starteTracking, stoppeTracking, watchdogState,
} from '../location/task';
import { pruefe, statuszeile } from '../location/watchdog';
import { warneSystem } from '../audio/player';
import { datasetOrNull } from '../core/dataset';
import { distanceToNearest } from '../core/warn';
import { warnmodus } from '../core/country';
import type { LandCode } from '../config';
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
  /*
   * Das Land nach der GATE-Tabelle, nicht der erkannte Umriss.
   *
   * Vorher stand hier landStatus().umriss — also auch Codes wie GB oder IE,
   * für die es gar keinen Gate-Eintrag gibt. Für DE, AT und CH fällt das
   * zusammen, überall sonst nicht: warnmodus() und bannerFuerLand() lesen die
   * Gate-Tabelle, und ein Umriss ohne Eintrag ist dort kein gültiger
   * Schlüssel.
   */
  const [land, setLand] = useState<LandCode | null>(null);

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
      puls.setValue(DECKKRAFT.VOLL);
      return;
    }
    const schleife = Animated.loop(
      Animated.sequence([
        Animated.timing(puls, {
          toValue: DECKKRAFT.PULS_TIEF, duration: DAUER.PULS, useNativeDriver: true,
        }),
        Animated.timing(puls, {
          toValue: DECKKRAFT.VOLL, duration: DAUER.PULS, useNativeDriver: true,
        }),
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

      setLand(landStatus().land);

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

  /*
   * Der Rechtshinweis kommt aus strings.bannerFuerLand() und nicht aus einer
   * Bedingung hier.
   *
   * Vorher stand hier `land === 'DE' || land === 'AT' || land === 'CH'`, und
   * bannerFuerLand() war toter Code — genau das, was der Kommentar dieser
   * Funktion verhindern sollte. Ein neuer Eintrag mit hinweisBanner: true
   * hätte nie einen Banner bekommen, und der Banner ist eine rechtliche
   * Anforderung, keine Verzierung.
   */
  const banner = bannerFuerLand(land);

  /*
   * Die Statuszeile sagt, was die Warnung TUT — nicht, ob das Tracking läuft.
   *
   * Vorher stand dort `STRINGS.fahrt.status.aktiv` ("Warnung aktiv"), sobald
   * die Positionsverfolgung lief. In einem Land, in dem das Gate abschaltet,
   * behauptete die App damit "Warnung aktiv" direkt über einem Banner, der
   * das Gegenteil sagte. Ein Widerspruch auf demselben Bildschirm ist
   * schlimmer als eine fehlende Zeile: Er lässt den Fahrer raten, welche der
   * beiden Angaben stimmt.
   */
  const modus = warnmodus(land);
  const statusText =
    modus === 'aus'
      ? STRINGS.fahrt.status.landGesperrt
      : modus === 'zone'
        ? STRINGS.zone.aktiv
        : STRINGS.fahrt.status.aktiv;

  return (
    <View style={[stil.wurzel, { backgroundColor: farben.hintergrund }]}>
      <ScrollView contentContainerStyle={stil.inhalt}>

        {/* Rechtshinweis-Banner. Nicht abschaltbar (Spec 2). */}
        {banner != null && (
          <View
            style={[stil.banner, { borderColor: farben.warn, backgroundColor: farben.warnGedaempft }]}
            accessibilityRole="alert"
          >
            <Text style={[stil.bannerText, { color: farben.text }]}>
              {banner.kurz}
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
              {
                backgroundColor: aktiv ? farben.warn : farben.textInaktiv,
                opacity: aktiv ? puls : DECKKRAFT.VOLL,
              },
            ]}
          />
          <Text style={[stil.status, { color: farben.textSekundaer }]}>
            {!aktiv
              ? STRINGS.fahrt.status.inaktiv
              : `${statusText}` +
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
        style={(z) => [
          stil.knopf,
          { backgroundColor: aktiv ? farben.warnGedaempft : farben.warn, borderColor: farben.warn },
          gedrueckt(z),
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
          style={(z) => [stil.fussKnopf, gedrueckt(z)]}
          accessibilityRole="button"
          accessibilityLabel={STRINGS.einstellungen.titel}
        >
          <Text style={[stil.fussText, { color: farben.textSekundaer }]}>
            {STRINGS.einstellungen.titel}
          </Text>
        </Pressable>
        <Pressable
          onPress={onOeffneInfo}
          style={(z) => [stil.fussKnopf, gedrueckt(z)]}
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
  inhalt: { padding: ABSTAND.RAND, paddingTop: SEITE.OBEN_FAHRT, gap: SEITE.BLOCK_FAHRT },
  banner: { borderWidth: LINIE.DUENN, borderRadius: RADIUS.S, padding: ABSTAND.L, gap: ABSTAND.S },
  bannerTitel: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.FETT },
  bannerText: { fontSize: SCHRIFT.KLEIN, lineHeight: SCHRIFT.KLEIN * ZEILENHOEHE.TEXT },
  tachoBlock: { alignItems: 'center', gap: ABSTAND.XS },
  tacho: { fontSize: SCHRIFT.TACHO, letterSpacing: spur(SCHRIFT.TACHO), fontWeight: GEWICHT.FETT, lineHeight: SCHRIFT.TACHO * ZEILENHOEHE.ZAHL },
  tachoEinheit: { fontSize: SCHRIFT.TACHO_EINHEIT },
  anlageBlock: { alignItems: 'center', gap: ABSTAND.XS },
  label: { fontSize: SCHRIFT.LABEL, textTransform: 'uppercase', letterSpacing: SPUR.VERSALIEN },
  entfernung: {
    fontSize: SCHRIFT.WARN_ENTFERNUNG, letterSpacing: spur(SCHRIFT.WARN_ENTFERNUNG),
    lineHeight: SCHRIFT.WARN_ENTFERNUNG * ZEILENHOEHE.ZAHL, fontWeight: GEWICHT.MITTEL,
  },
  statusZeile: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: ABSTAND.S },
  punkt: { width: MASS.PUNKT, height: MASS.PUNKT, borderRadius: RADIUS.KREIS },
  status: { fontSize: SCHRIFT.STATUS },
  leer: { borderWidth: LINIE.DUENN, borderRadius: RADIUS.S, padding: ABSTAND.L, gap: ABSTAND.S },
  knopf: {
    marginHorizontal: ABSTAND.RAND, marginBottom: ABSTAND.M, minHeight: TOUCH.MIN,
    borderWidth: LINIE.DICK, borderRadius: RADIUS.M, alignItems: 'center', justifyContent: 'center',
  },
  knopfText: {
    fontSize: SCHRIFT.WARN_TITEL, letterSpacing: spur(SCHRIFT.WARN_TITEL),
    lineHeight: SCHRIFT.WARN_TITEL * ZEILENHOEHE.ENG, fontWeight: GEWICHT.FETT,
  },
  fussZeile: { flexDirection: 'row', justifyContent: 'space-around', paddingBottom: ABSTAND.XL },
  fussKnopf: { minHeight: TOUCH.MIN, minWidth: TOUCH.MIN, justifyContent: 'center', paddingHorizontal: ABSTAND.RAND },
  fussText: { fontSize: SCHRIFT.TEXT },
});
