/**
 * Umgebung — was die App an diesem Ort weiss, als Bild.
 *
 * WAS DIESE KARTE IST UND WAS SIE NICHT IST
 *
 * Sie zeigt die erfassten Anlagen, die eigene Position und die Landesumrisse,
 * Norden oben, mit Entfernungsringen und Massstabsbalken. Sie zeigt KEINE
 * STRASSEN. Das ist keine Sparmassnahme: Eine übliche Karte lädt Kacheln über
 * das Netz nach, und damit wäre das Produktversprechen dahin.
 * Strassengeometrie offline mitzuliefern wären für Deutschland allein
 * hunderte Megabyte; die ganze App wiegt vier.
 *
 * Die Landesumrisse sind der einzige echte Kartenhintergrund, den es ohne Netz
 * geben kann: Das Länder-Gate braucht sie ohnehin, sie liegen schon im Paket
 * und sind Public Domain. An einer Küste oder in Grenznähe machen sie aus
 * einem Punktfeld ein Bild. Mitten in Bayern bleibt es ein Punktfeld — und
 * dann steht das auch da.
 *
 * WARUM SIE NICHT AUF DEM FAHRT-SCHIRM LIEGT
 *
 * Weil sie dort schaden würde. Der Fahrt-Screen ist für einen Blick von einer
 * halben Sekunde gebaut; eine Karte lädt zum Studieren ein. Ihr Zweck ist der
 * Stand: nachsehen, ob für die Gegend überhaupt Daten da sind.
 *
 * WARUM react-native-svg UND NICHT VIEWS
 *
 * Die erste Fassung zeichnete mit gewöhnlichen Views. Das trug Punkte und
 * Kreise, aber nicht Linienzüge: Ein Umriss aus hundert Abschnitten wären
 * hundert einzeln gedrehte Views, und die Richtungskeile kämen noch dazu.
 * react-native-svg ist dafür das vorgesehene Werkzeug, rendert nativ und
 * stellt keine Netzwerkverbindung her — tests/auslieferung.test.ts führt es
 * deshalb ausdrücklich als erlaubt.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  PanResponder, Pressable, ScrollView, StyleSheet, Text, View, useWindowDimensions,
} from 'react-native';
import Svg, { Circle, G, Line, Polyline } from 'react-native-svg';

import { KARTE } from '../config';
import { STRINGS } from '../strings';
import {
  baueKarte, massstabsbalken, punktBeiTipp, umrissAbRadiusM, umrissLinien, verschiebe,
  type Bildpunkt, type Karte, type Linienzug,
} from '../core/karte';
import { camerasInRadius, datasetOrNull } from '../core/dataset';
import { letzterFix } from '../location/task';
import { errorLog } from '../core/log';
import {
  ABSTAND, GEWICHT, LINIE, MASS, RADIUS, SCHRIFT, SEITE, SPUR, TOUCH, ZEILENHOEHE,
  gedrueckt, palette, spur, type Palette, type ThemeMode,
} from './theme';

type Props = { mode: ThemeMode; onZurueck: () => void };

/**
 * Wie oft die Karte nachzieht.
 *
 * Eine Sekunde, wie auf dem Fahrt-Screen: Der Task läuft in einem eigenen
 * JS-Kontext und kann React nicht anstossen, also wird gepollt. Die Zahl
 * steht hier und nicht in config.ts, weil sie nur die Anzeigefrequenz dieses
 * Screens bestimmt und keine Entscheidung auslöst.
 */
const AKTUALISIERUNG_MS = 1000;

export default function KarteScreen({ mode, onZurueck }: Props) {
  const farben = palette(mode);
  const { width } = useWindowDimensions();
  const [radiusM, setRadiusM] = useState<number>(KARTE.START_RADIUS_M);
  const [fix, setFix] = useState(() => letzterFix());
  const [gewaehlt, setGewaehlt] = useState<Bildpunkt | null>(null);

  /**
   * Der Bildmittelpunkt, wenn er nicht die eigene Position ist.
   *
   * null heisst "folge mir". Sobald jemand zieht, steht hier eine feste
   * Position und die Karte hört auf mitzuwandern — sonst würde sie unter dem
   * Finger wegrutschen, sobald der nächste Fix eintrifft.
   */
  const [verschoben, setVerschoben] = useState<{ lat: number; lon: number } | null>(null);

  // Quadratisch, so breit wie der Inhalt. Der Rand kommt zweimal weg.
  const groesse = Math.max(0, width - ABSTAND.RAND * 2);

  useEffect(() => {
    const timer = setInterval(() => setFix(letzterFix()), AKTUALISIERUNG_MS);
    return () => clearInterval(timer);
  }, []);

  const dataset = datasetOrNull();
  const mitte = verschoben ?? (fix === null ? null : { lat: fix.lat, lon: fix.lon });

  const karte = useMemo(() => {
    if (mitte === null || dataset === null) return null;
    try {
      const cams = camerasInRadius(dataset, mitte.lat, mitte.lon, radiusM);
      if (cams === null) return null;
      return baueKarte(mitte.lat, mitte.lon, cams, groesse, radiusM);
    } catch (err) {
      errorLog.error('start', 'Karte konnte nicht berechnet werden', err);
      return null;
    }
  }, [mitte?.lat, mitte?.lon, dataset, radiusM, groesse]);

  const umrisse = useMemo(
    () => (mitte === null ? [] : umrissLinien(mitte.lat, mitte.lon, groesse, radiusM)),
    [mitte?.lat, mitte?.lon, groesse, radiusM],
  );

  /*
   * Ziehen.
   *
   * PanResponder statt einer Gestenbibliothek: Verschieben ist die einzige
   * Geste, die diese Karte braucht — gezoomt wird über die Stufen, weil die
   * Umkreise ohnehin fest sind und ein stufenloser Zoom nur die Frage
   * aufwürfe, was für ein Umkreis gerade eingestellt ist.
   *
   * Der Anfangsmittelpunkt wird beim Griff festgehalten. Würde jede Bewegung
   * relativ zur schon verschobenen Karte gerechnet, summierten sich die
   * cos(Breite)-Umrechnungen und die Karte driftete unter dem Finger.
   */
  const griff = useRef<{ lat: number; lon: number } | null>(null);
  const gezogen = useRef(false);

  const pan = useMemo(
    () => PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onMoveShouldSetPanResponder: (_e, g) => Math.hypot(g.dx, g.dy) > LINIE.DICK,
      onPanResponderGrant: () => {
        griff.current = mitte;
        gezogen.current = false;
      },
      onPanResponderMove: (_e, g) => {
        const start = griff.current;
        if (start === null) return;
        if (Math.hypot(g.dx, g.dy) > LINIE.DICK) gezogen.current = true;
        setVerschoben(verschiebe(start.lat, start.lon, g.dx, g.dy, groesse, radiusM));
      },
      onPanResponderRelease: (e) => {
        // Ein Tipp ist eine Berührung ohne nennenswerte Bewegung. Nur dann
        // wird ausgewählt — sonst wählte jedes Verschieben nebenbei etwas aus.
        if (gezogen.current || karte === null) return;
        const { locationX, locationY } = e.nativeEvent;
        setGewaehlt(punktBeiTipp(karte, locationX, locationY));
      },
    }),
    [mitte?.lat, mitte?.lon, groesse, radiusM, karte],
  );

  const zurueckZuMir = useCallback(() => {
    setVerschoben(null);
    setGewaehlt(null);
  }, []);

  const gesamtImUmkreis = karte === null ? 0 : karte.punkte.length + karte.nichtGezeichnet;
  const balken = massstabsbalken(groesse, radiusM);

  return (
    <ScrollView
      style={{ backgroundColor: farben.hintergrund }}
      contentContainerStyle={stil.inhalt}
      // Sonst kämpft der Bildlauf mit dem Ziehen auf der Karte.
      scrollEnabled={!gezogen.current}
    >
      <Text style={[stil.titel, { color: farben.text }]}>{STRINGS.karte.titel}</Text>

      {/* Die Einschränkung zuerst, nicht als Fussnote. */}
      <Text style={[stil.hinweis, { color: farben.textSekundaer }]}>
        {STRINGS.karte.keineStrassen}
      </Text>

      <Text style={[stil.gruppe, { color: farben.textLeise }]}>{STRINGS.karte.radius}</Text>
      <View style={stil.stufen}>
        {KARTE.RADIEN_M.map((r) => {
          const aktiv = r === radiusM;
          return (
            <Pressable
              key={r}
              onPress={() => { setRadiusM(r); setGewaehlt(null); }}
              style={(z) => [
                stil.stufe,
                {
                  borderColor: aktiv ? farben.warn : farben.linie,
                  backgroundColor: aktiv ? farben.warnGedaempft : 'transparent',
                },
                gedrueckt(z),
              ]}
              accessibilityRole="button"
              accessibilityState={{ selected: aktiv }}
              accessibilityLabel={`${STRINGS.karte.radius} ${meter(r)}`}
            >
              <Text style={[stil.stufeText, { color: aktiv ? farben.warn : farben.text }]}>
                {meter(r)}
              </Text>
            </Pressable>
          );
        })}
      </View>

      {fix === null ? (
        <View style={[stil.leer, { borderColor: farben.linie, backgroundColor: farben.flaeche }]}>
          <Text style={[stil.leerTitel, { color: farben.text }]}>
            {STRINGS.karte.warteAufPosition}
          </Text>
          <Text style={[stil.klein, { color: farben.textSekundaer }]}>
            {STRINGS.karte.warteAufPositionHilfe}
          </Text>
        </View>
      ) : dataset === null || karte === null ? (
        <View style={[stil.leer, { borderColor: farben.linie, backgroundColor: farben.flaeche }]}>
          <Text style={[stil.leerTitel, { color: farben.text }]}>
            {STRINGS.karte.keineDaten}
          </Text>
        </View>
      ) : (
        <View {...pan.panHandlers}>
          <KartenBild
            karte={karte}
            umrisse={umrisse}
            ichSichtbar={verschoben === null}
            gewaehlt={gewaehlt}
            balken={balken}
            farben={farben}
          />
        </View>
      )}

      {/* Verschoben? Dann muss ein Weg zurück da sein, sonst ist die Karte
          verloren, sobald jemand einmal zu weit gezogen hat. */}
      {verschoben !== null && (
        <Pressable
          onPress={zurueckZuMir}
          style={(z) => [stil.link, { borderColor: farben.warn }, gedrueckt(z)]}
          accessibilityRole="button"
          accessibilityLabel={STRINGS.karte.zurueckZuMir}
        >
          <Text style={[stil.linkText, { color: farben.warn }]}>
            {STRINGS.karte.zurueckZuMir}
          </Text>
        </Pressable>
      )}

      {/* Die angetippte Anlage. */}
      {gewaehlt !== null && (
        <View style={[stil.karteInfo, { borderColor: farben.warn, backgroundColor: farben.flaeche }]}>
          <Text style={[stil.text, { color: farben.text }]}>
            {STRINGS.karte.anlagenArt[gewaehlt.camera.type]}
          </Text>
          <Text style={[stil.klein, { color: farben.textSekundaer }]}>
            {`${Math.round(gewaehlt.distanzM)} m` +
              (gewaehlt.camera.max !== null ? ` · ${STRINGS.karte.tempolimit} ${gewaehlt.camera.max}` : '') +
              (gewaehlt.camera.dir !== null ? ` · ${STRINGS.karte.blickrichtung} ${Math.round(gewaehlt.camera.dir)}°` : '')}
          </Text>
          {gewaehlt.camera.dir === null && (
            <Text style={[stil.klein, { color: farben.textLeise }]}>
              {STRINGS.karte.keineRichtung}
            </Text>
          )}
        </View>
      )}

      {karte !== null && (
        <View style={[stil.karteInfo, { borderColor: farben.linie, backgroundColor: farben.flaeche }]}>
          {gesamtImUmkreis === 0 ? (
            <>
              <Text style={[stil.text, { color: farben.text }]}>
                {STRINGS.karte.keineAnlagen}
              </Text>
              <Text style={[stil.klein, { color: farben.textLeise }]}>
                {STRINGS.karte.keineAnlagenHilfe}
              </Text>
            </>
          ) : (
            <>
              <Text style={[stil.text, { color: farben.text }]}>
                {STRINGS.karte.anlagenImUmkreis(gesamtImUmkreis)}
              </Text>
              {karte.punkte.length > 0 && (
                <Text style={[stil.klein, { color: farben.textSekundaer }]}>
                  {`${STRINGS.karte.naechste}: ${Math.round(karte.punkte[0]!.distanzM)} m`}
                </Text>
              )}
            </>
          )}

          {karte.nichtGezeichnet > 0 && (
            <Text style={[stil.klein, { color: farben.warn }]}>
              {STRINGS.karte.abgeschnitten(karte.nichtGezeichnet, gesamtImUmkreis)}
            </Text>
          )}

          {/* Warum die Grenzlinie fehlt — statt dass jemand rätselt. */}
          {radiusM < umrissAbRadiusM() && (
            <Text style={[stil.klein, { color: farben.textLeise }]}>
              {STRINGS.karte.umrissZuUngenau(Math.round(umrissAbRadiusM() / 1000))}
            </Text>
          )}
          <Text style={[stil.klein, { color: farben.textLeise }]}>
            {STRINGS.karte.bedienung}
          </Text>
        </View>
      )}

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

/** Meter oder Kilometer, je nachdem was kürzer zu lesen ist. */
function meter(m: number): string {
  return m < 1000 ? `${m} m` : `${m / 1000} km`;
}

/**
 * Das Bild selbst — reine Anzeige über einer fertig gerechneten Karte.
 *
 * Getrennt vom Screen und exportiert, damit der Rendertest den gezeichneten
 * Zustand überhaupt erreichen kann: Im Test liefert letzterFix() immer null,
 * der Screen zeigt dann seinen Wartezustand, und die Punkte bekäme nie jemand
 * zu sehen. Mit einer Komponente über explizitem Zustand lässt sich eine
 * Karte hineingeben und nachzählen, was herauskommt.
 */
export function KartenBild({
  karte, umrisse, ichSichtbar, gewaehlt, balken, farben,
}: {
  karte: Karte;
  umrisse: readonly Linienzug[];
  ichSichtbar: boolean;
  gewaehlt: Bildpunkt | null;
  balken: { meter: number; laengeDp: number };
  farben: Palette;
}) {
  const g = karte.groesseDp;
  const mitte = g / 2;

  return (
    <View style={[stil.bild, { width: g, height: g, borderColor: farben.linie }]}>
      <Svg width={g} height={g} accessibilityLabel={STRINGS.karte.bildBeschreibung}>
        {/* Landesumrisse zuunterst — sie sind Hintergrund, nicht Inhalt. */}
        <G>
          {umrisse.map((zug, i) => (
            <Polyline
              key={`u${i}`}
              points={zug.map((p) => `${p.x},${p.y}`).join(' ')}
              fill="none"
              stroke={farben.textLeise}
              strokeWidth={LINIE.DUENN}
            />
          ))}
        </G>

        {/* Entfernungsringe. Ohne sie hat das Bild keinen Massstab. */}
        <G>
          {karte.ringeM.map((r) => (
            <Circle
              key={r}
              cx={mitte} cy={mitte}
              r={(r / karte.radiusM) * mitte}
              fill="none"
              stroke={farben.linie}
              strokeWidth={LINIE.DUENN}
            />
          ))}
        </G>

        {/* Die Anlagen. Die Art wird über die Form unterschieden, nicht über
            eine zweite Farbe — es gibt genau eine Akzentfarbe. */}
        <G>
          {karte.punkte.map((p, i) => (
            <Anlagenzeichen
              key={`a${p.camera.lat},${p.camera.lon},${i}`}
              punkt={p}
              gewaehlt={gewaehlt === p}
              farben={farben}
            />
          ))}
        </G>

        {/* Die eigene Position, zuletzt gezeichnet und damit obenauf. Nur
            wenn die Karte ihr auch folgt — eine verschobene Karte hätte sonst
            einen Marker in der Mitte, der dort nichts bedeutet. */}
        {ichSichtbar && (
          <Circle
            cx={mitte} cy={mitte} r={MASS.KARTE_ICH / 2}
            fill={farben.hintergrund}
            stroke={farben.text}
            strokeWidth={LINIE.DICK}
          />
        )}

        {/* Massstabsbalken unten links. */}
        <G>
          <Line
            x1={ABSTAND.S} y1={g - ABSTAND.L}
            x2={ABSTAND.S + balken.laengeDp} y2={g - ABSTAND.L}
            stroke={farben.text} strokeWidth={LINIE.DICK}
          />
          <Line
            x1={ABSTAND.S} y1={g - ABSTAND.L - ABSTAND.XS}
            x2={ABSTAND.S} y2={g - ABSTAND.L + ABSTAND.XS}
            stroke={farben.text} strokeWidth={LINIE.DICK}
          />
          <Line
            x1={ABSTAND.S + balken.laengeDp} y1={g - ABSTAND.L - ABSTAND.XS}
            x2={ABSTAND.S + balken.laengeDp} y2={g - ABSTAND.L + ABSTAND.XS}
            stroke={farben.text} strokeWidth={LINIE.DICK}
          />
        </G>
      </Svg>

      {/*
        Die Beschriftung des Balkens als gewöhnlicher Text und nicht als
        SVG-Text: react-native-svg setzt Schrift auf beiden Plattformen
        unterschiedlich, und die Schriftgrade dieser App sind gemessen.
      */}
      <Text
        style={[stil.balkenText, { color: farben.text, left: ABSTAND.S, bottom: ABSTAND.S }]}
      >
        {meter(balken.meter)}
      </Text>
    </View>
  );
}

/**
 * Eine Anlage im Bild.
 *
 * Die Art wird über die Form unterschieden und nicht über eine zweite Farbe:
 * Es gibt genau eine Akzentfarbe, und jede weitere entwertet sie (siehe
 * theme.ts). Gefüllt = Geschwindigkeit, hohl = Rotlicht, gefüllt mit Ring =
 * beides.
 *
 * Der Strich zeigt die Blickrichtung, wo sie erfasst ist — bei rund einem
 * Drittel der Einträge. Fehlt sie, fehlt auch der Strich; eine geratene
 * Richtung wäre schlimmer als keine.
 */
function Anlagenzeichen({
  punkt, gewaehlt, farben,
}: { punkt: Bildpunkt; gewaehlt: boolean; farben: Palette }) {
  const r = MASS.KARTE_ANLAGE / 2;
  const { type, dir } = punkt.camera;
  const gefuellt = type === 'speed' || type === 'both';

  // Der Richtungsstrich ist so lang wie der Punkt breit — länger würde er bei
  // dicht stehenden Anlagen zum Liniengewirr.
  const laenge = MASS.KARTE_ANLAGE;
  const bogen = dir === null ? 0 : ((dir - 90) * Math.PI) / 180;

  return (
    <G>
      {dir !== null && (
        <Line
          x1={punkt.x} y1={punkt.y}
          x2={punkt.x + Math.cos(bogen) * laenge}
          y2={punkt.y + Math.sin(bogen) * laenge}
          stroke={farben.warn}
          strokeWidth={LINIE.DUENN}
        />
      )}
      <Circle
        cx={punkt.x} cy={punkt.y} r={r}
        fill={gefuellt ? farben.warn : 'none'}
        stroke={farben.warn}
        strokeWidth={LINIE.DUENN}
      />
      {type === 'both' && (
        <Circle
          cx={punkt.x} cy={punkt.y} r={r + LINIE.DICK}
          fill="none" stroke={farben.warn} strokeWidth={LINIE.DUENN}
        />
      )}
      {gewaehlt && (
        <Circle
          cx={punkt.x} cy={punkt.y} r={MASS.KARTE_ICH}
          fill="none" stroke={farben.text} strokeWidth={LINIE.DICK}
        />
      )}
    </G>
  );
}

const stil = StyleSheet.create({
  inhalt: { padding: ABSTAND.RAND, paddingTop: SEITE.OBEN, gap: ABSTAND.M, paddingBottom: SEITE.UNTEN },
  titel: {
    fontSize: SCHRIFT.WARN_TITEL, letterSpacing: spur(SCHRIFT.WARN_TITEL),
    lineHeight: SCHRIFT.WARN_TITEL * ZEILENHOEHE.ENG, fontWeight: GEWICHT.FETT,
  },
  hinweis: { fontSize: SCHRIFT.KLEIN, lineHeight: SCHRIFT.KLEIN * ZEILENHOEHE.TEXT },
  gruppe: {
    fontSize: SCHRIFT.LABEL, textTransform: 'uppercase',
    letterSpacing: SPUR.VERSALIEN, marginTop: ABSTAND.S,
  },
  stufen: { flexDirection: 'row', gap: ABSTAND.S },
  stufe: {
    flex: 1, minHeight: TOUCH.MIN, borderWidth: LINIE.DUENN, borderRadius: RADIUS.S,
    alignItems: 'center', justifyContent: 'center',
  },
  stufeText: { fontSize: SCHRIFT.LABEL, fontWeight: GEWICHT.MITTEL },
  bild: { borderWidth: LINIE.DUENN, borderRadius: RADIUS.M, overflow: 'hidden' },
  balkenText: { position: 'absolute', fontSize: SCHRIFT.KLEIN, fontWeight: GEWICHT.MITTEL },
  karteInfo: { borderWidth: LINIE.DUENN, borderRadius: RADIUS.M, padding: ABSTAND.L, gap: ABSTAND.S },
  leer: { borderWidth: LINIE.DUENN, borderRadius: RADIUS.M, padding: ABSTAND.L, gap: ABSTAND.S },
  leerTitel: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.FETT },
  text: { fontSize: SCHRIFT.TEXT, lineHeight: SCHRIFT.TEXT * ZEILENHOEHE.TEXT },
  klein: { fontSize: SCHRIFT.KLEIN, lineHeight: SCHRIFT.KLEIN * ZEILENHOEHE.TEXT },
  link: {
    minHeight: TOUCH.MIN, borderWidth: LINIE.DUENN, borderRadius: RADIUS.S,
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: ABSTAND.M,
  },
  linkText: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.MITTEL },
  knopf: {
    marginTop: ABSTAND.XL, minHeight: TOUCH.MIN, borderWidth: LINIE.DUENN, borderRadius: RADIUS.M,
    alignItems: 'center', justifyContent: 'center',
  },
  knopfText: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.MITTEL },
});
