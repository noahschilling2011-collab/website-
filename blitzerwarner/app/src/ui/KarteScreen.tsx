/**
 * Umgebung — was die App an diesem Ort weiss, als Bild.
 *
 * WAS DIESE KARTE IST UND WAS SIE NICHT IST
 *
 * Sie zeigt die erfassten Anlagen und die eigene Position, Norden oben.
 * Sie zeigt KEINE Strassen. Das ist keine Sparmassnahme: Eine übliche Karte
 * lädt Kacheln über das Netz nach, und damit wäre das Produktversprechen
 * dahin. Strassengeometrie offline mitzuliefern wären für Deutschland allein
 * hunderte Megabyte; die ganze App wiegt vier.
 *
 * Der Hinweis darauf steht ÜBER der Karte und nicht klein darunter. Wer sie
 * für eine Navigationskarte hält und dann merkt, dass sie keine ist, hält die
 * App für kaputt statt für ehrlich.
 *
 * WARUM SIE NICHT AUF DEM FAHRT-SCHIRM LIEGT
 *
 * Weil sie dort schaden würde. Der Fahrt-Screen ist für einen Blick von einer
 * halben Sekunde gebaut; eine Karte lädt zum Studieren ein. Und ohne Strassen
 * beantwortet sie unterwegs ohnehin keine Frage, die die Ansage nicht besser
 * beantwortet. Ihr Zweck ist der Stand: nachsehen, ob für die Gegend
 * überhaupt Daten da sind, bevor man losfährt.
 *
 * Gezeichnet wird mit gewöhnlichen Views, nicht mit einer Grafikbibliothek.
 * Punkte und Ringe sind Rechtecke mit Eckenradius — dafür lohnt keine
 * zusätzliche Abhängigkeit, und jede zusätzliche Abhängigkeit ist eine
 * weitere, die zur Laufzeit etwas tun könnte.
 */
import { useEffect, useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View, useWindowDimensions } from 'react-native';

import { KARTE } from '../config';
import { STRINGS } from '../strings';
import { baueKarte, projiziere, type Karte } from '../core/karte';
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

  // Quadratisch, so breit wie der Inhalt. Der Rand kommt zweimal weg.
  const groesse = Math.max(0, width - ABSTAND.RAND * 2);

  useEffect(() => {
    const timer = setInterval(() => setFix(letzterFix()), AKTUALISIERUNG_MS);
    return () => clearInterval(timer);
  }, []);

  const dataset = datasetOrNull();

  const karte = useMemo(() => {
    if (fix === null || dataset === null) return null;
    try {
      const cams = camerasInRadius(dataset, fix.lat, fix.lon, radiusM);
      if (cams === null) return null;
      return baueKarte(fix.lat, fix.lon, cams, groesse, radiusM);
    } catch (err) {
      errorLog.error('start', 'Karte konnte nicht berechnet werden', err);
      return null;
    }
  }, [fix, dataset, radiusM, groesse]);

  const gesamtImUmkreis =
    karte === null ? 0 : karte.punkte.length + karte.nichtGezeichnet;

  const ich = fix === null
    ? { x: 0, y: 0 }
    : projiziere(fix.lat, fix.lon, fix.lat, fix.lon, groesse, radiusM);

  return (
    <ScrollView
      style={{ backgroundColor: farben.hintergrund }}
      contentContainerStyle={stil.inhalt}
    >
      <Text style={[stil.titel, { color: farben.text }]}>{STRINGS.karte.titel}</Text>

      {/* Die Einschränkung zuerst, nicht als Fussnote. */}
      <Text style={[stil.hinweis, { color: farben.textSekundaer }]}>
        {STRINGS.karte.keineStrassen}
      </Text>

      {/* Umkreis wählen. */}
      <Text style={[stil.gruppe, { color: farben.textLeise }]}>{STRINGS.karte.radius}</Text>
      <View style={stil.stufen}>
        {KARTE.RADIEN_M.map((r) => {
          const aktiv = r === radiusM;
          return (
            <Pressable
              key={r}
              onPress={() => setRadiusM(r)}
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

      {/* Das Bild — oder der Grund, warum es keines gibt. */}
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
        <KartenBild karte={karte} ich={ich} farben={farben} />
      )}

      {/* Was im Bild steht, noch einmal in Worten — für die Sprachausgabe
          und für alle, die Punkte nicht zählen wollen. */}
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

          {/* Nur wenn wirklich abgeschnitten wurde. Eine unvollständige
              Karte, die vollständig aussieht, ist schlimmer als gar keine. */}
          {karte.nichtGezeichnet > 0 && (
            <Text style={[stil.klein, { color: farben.warn }]}>
              {STRINGS.karte.abgeschnitten(karte.nichtGezeichnet, gesamtImUmkreis)}
            </Text>
          )}
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
 * der Screen zeigt dann seinen Wartezustand, und die Punkte bekäme nie
 * jemand zu sehen. Mit einer Komponente über explizitem Zustand lässt sich
 * eine Karte hineingeben und nachzählen, was herauskommt.
 *
 * Dieselbe Trennung wie in core/: rechnen und darstellen sind zwei Dinge.
 */
export function KartenBild({
  karte, ich, farben,
}: {
  karte: Karte;
  ich: { x: number; y: number };
  farben: Palette;
}) {
  const g = karte.groesseDp;
  return (
    <View
      style={[stil.bild, { width: g, height: g, borderColor: farben.linie }]}
      accessibilityLabel={STRINGS.karte.anlagenImUmkreis(
        karte.punkte.length + karte.nichtGezeichnet,
      )}
    >
      {/* Entfernungsringe. Ohne sie hat das Bild keinen Massstab. */}
      {karte.ringeM.map((r) => {
        const d = (r / karte.radiusM) * g;
        return (
          <View
            key={r}
            pointerEvents="none"
            style={[
              stil.ring,
              { width: d, height: d, left: (g - d) / 2, top: (g - d) / 2, borderColor: farben.linie },
            ]}
          />
        );
      })}

      {/* Die Anlagen. */}
      {karte.punkte.map((p, i) => (
        <View
          key={`${p.camera.lat},${p.camera.lon},${i}`}
          pointerEvents="none"
          style={[
            stil.anlage,
            {
              left: p.x - MASS.KARTE_ANLAGE / 2,
              top: p.y - MASS.KARTE_ANLAGE / 2,
              backgroundColor: farben.warn,
            },
          ]}
        />
      ))}

      {/*
        Die eigene Position, zuletzt gezeichnet und damit obenauf.

        Sie liegt immer genau in der Mitte — die Karte ist um sie herum
        aufgebaut. Trotzdem geht sie durch dieselbe Projektion wie alles
        andere: Sollte die Mitte eines Tages nicht mehr die eigene Position
        sein (verschiebbare Karte), stimmt sie dann noch.
      */}
      <View
        pointerEvents="none"
        style={[
          stil.ich,
          {
            left: ich.x - MASS.KARTE_ICH / 2,
            top: ich.y - MASS.KARTE_ICH / 2,
            borderColor: farben.text,
            backgroundColor: farben.hintergrund,
          },
        ]}
      />
    </View>
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
  ring: { position: 'absolute', borderWidth: LINIE.DUENN, borderRadius: RADIUS.KREIS },
  anlage: {
    position: 'absolute', width: MASS.KARTE_ANLAGE, height: MASS.KARTE_ANLAGE,
    borderRadius: RADIUS.KREIS,
  },
  ich: {
    position: 'absolute', width: MASS.KARTE_ICH, height: MASS.KARTE_ICH,
    borderRadius: RADIUS.KREIS, borderWidth: LINIE.DICK,
  },
  karteInfo: { borderWidth: LINIE.DUENN, borderRadius: RADIUS.M, padding: ABSTAND.L, gap: ABSTAND.S },
  leer: { borderWidth: LINIE.DUENN, borderRadius: RADIUS.M, padding: ABSTAND.L, gap: ABSTAND.S },
  leerTitel: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.FETT },
  text: { fontSize: SCHRIFT.TEXT, lineHeight: SCHRIFT.TEXT * ZEILENHOEHE.TEXT },
  klein: { fontSize: SCHRIFT.KLEIN, lineHeight: SCHRIFT.KLEIN * ZEILENHOEHE.TEXT },
  knopf: {
    marginTop: ABSTAND.XL, minHeight: TOUCH.MIN, borderWidth: LINIE.DUENN, borderRadius: RADIUS.M,
    alignItems: 'center', justifyContent: 'center',
  },
  knopfText: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.MITTEL },
});
