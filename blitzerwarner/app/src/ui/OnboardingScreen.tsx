/**
 * Onboarding — Rechtshinweis, Berechtigungen, Datenstand.
 *
 * Der Rechtshinweis ist bestätigungspflichtig (Spec 2): Der Weiter-Knopf
 * bleibt gesperrt, bis der Nutzer aktiv zugestimmt hat. Kein "Später", das
 * nichts tut, kein Bewertungs-Popup, keine Push-Nachfrage ausser für die
 * technisch nötige Foreground-Notification.
 */
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';
import * as Location from 'expo-location';

import { STRINGS } from '../strings';
import {
  ABSTAND, GEWICHT, LINIE, RADIUS, SCHRIFT, SEITE, TOUCH, ZEILENHOEHE,
  gedrueckt, palette, spur, type ThemeMode,
} from './theme';
import { useApp } from '../state/store';
import { datasetOrNull } from '../core/dataset';
import { errorLog } from '../core/log';

type Props = { mode: ThemeMode };

type Rechte = 'offen' | 'vordergrund' | 'hintergrund' | 'abgelehnt';

export default function OnboardingScreen({ mode }: Props) {
  const farben = palette(mode);
  const bestaetige = useApp((s) => s.bestaetigeRechtshinweis);

  const [gelesen, setGelesen] = useState(false);
  const [rechte, setRechte] = useState<Rechte>('offen');
  const dataset = datasetOrNull();

  /**
   * Berechtigungen in zwei Schritten anfordern.
   *
   * Android verlangt das so: Der Hintergrundzugriff lässt sich erst
   * erbitten, wenn der Vordergrundzugriff erteilt ist. Beides in einem
   * Aufruf zu verlangen scheitert stillschweigend.
   */
  async function frageRechte(): Promise<void> {
    try {
      const vorne = await Location.requestForegroundPermissionsAsync();
      if (vorne.status !== 'granted') {
        setRechte('abgelehnt');
        return;
      }
      setRechte('vordergrund');

      const hinten = await Location.requestBackgroundPermissionsAsync();
      setRechte(hinten.status === 'granted' ? 'hintergrund' : 'vordergrund');
    } catch (err) {
      errorLog.error('start', 'Berechtigungen konnten nicht angefordert werden', err);
      setRechte('abgelehnt');
    }
  }

  const kannWeiter = gelesen && (rechte === 'hintergrund' || rechte === 'vordergrund');

  return (
    <ScrollView
      style={{ backgroundColor: farben.hintergrund }}
      contentContainerStyle={stil.inhalt}
    >
      <Text style={[stil.titel, { color: farben.text }]}>
        {STRINGS.onboarding.willkommenTitel}
      </Text>
      <Text style={[stil.text, { color: farben.textSekundaer }]}>
        {STRINGS.onboarding.willkommenText}
      </Text>

      {/* Was die App NICHT kann, steht vor allem anderen — nicht im
          Kleingedruckten. Wer mobile Blitzer erwartet, soll es hier lesen. */}
      <View style={[stil.karte, { borderColor: farben.linie, backgroundColor: farben.flaeche }]}>
        <Text style={[stil.kartenTitel, { color: farben.text }]}>
          {STRINGS.onboarding.grenzenTitel}
        </Text>
        <Text style={[stil.text, { color: farben.textSekundaer }]}>
          {STRINGS.onboarding.grenzenText}
        </Text>
      </View>

      {/* Rechtshinweis */}
      <View style={[stil.karte, { borderColor: farben.warn, backgroundColor: farben.flaeche }]}>
        <Text style={[stil.kartenTitel, { color: farben.warn }]}>
          {STRINGS.onboarding.rechtTitel}
        </Text>
        <Text style={[stil.text, { color: farben.textSekundaer }]}>
          {STRINGS.onboarding.rechtNorm}
        </Text>
        <Text style={[stil.text, { color: farben.textSekundaer }]}>
          {STRINGS.onboarding.rechtSanktion}
        </Text>
        <Text style={[stil.text, { color: farben.textSekundaer }]}>
          {STRINGS.onboarding.rechtBeifahrer}
        </Text>
        <Text style={[stil.text, { color: farben.textSekundaer }]}>
          {STRINGS.onboarding.rechtFolge}
        </Text>
        <Text style={[stil.klein, { color: farben.textLeise }]}>
          {STRINGS.onboarding.rechtKeineBeratung}
        </Text>

        <View style={stil.schalterZeile}>
          <Switch
            value={gelesen}
            onValueChange={setGelesen}
            trackColor={{ false: farben.linie, true: farben.warn }}
            accessibilityLabel={STRINGS.onboarding.rechtBestaetigung}
          />
          <Text style={[stil.text, { color: farben.text, flex: 1 }]}>
            {STRINGS.onboarding.rechtBestaetigung}
          </Text>
        </View>
      </View>

      {/* Berechtigungen */}
      <View style={[stil.karte, { borderColor: farben.linie, backgroundColor: farben.flaeche }]}>
        <Text style={[stil.kartenTitel, { color: farben.text }]}>
          {STRINGS.onboarding.berechtigungTitel}
        </Text>
        <Text style={[stil.text, { color: farben.textSekundaer }]}>
          {STRINGS.onboarding.berechtigungText}
        </Text>

        <Text style={[stil.klein, { color: farben.textLeise }]}>
          {STRINGS.onboarding.berechtigungZweiSchritte}
        </Text>

        {rechte === 'vordergrund' && (
          <Text style={[stil.text, { color: farben.warn }]}>
            {STRINGS.fehler.standortRechtNurVordergrund.titel}
          </Text>
        )}
        {rechte === 'abgelehnt' && (
          <Text style={[stil.text, { color: farben.warn }]}>
            {STRINGS.fehler.standortRechtFehlt.handlung}
          </Text>
        )}

        <Pressable
          onPress={frageRechte}
          style={(z) => [stil.knopfKlein, { borderColor: farben.warn }, gedrueckt(z)]}
          accessibilityRole="button"
          accessibilityLabel={STRINGS.onboarding.berechtigungAnfordern}
        >
          <Text style={[stil.knopfKleinText, { color: farben.warn }]}>
            {rechte === 'hintergrund'
              ? STRINGS.onboarding.berechtigungErteilt
              : STRINGS.onboarding.berechtigungAnfordern}
          </Text>
        </Pressable>
      </View>

      {/* Datenstand — gehört sichtbar in die App, nicht ins Kleingedruckte. */}
      <View style={[stil.karte, { borderColor: farben.linie, backgroundColor: farben.flaeche }]}>
        <Text style={[stil.kartenTitel, { color: farben.text }]}>
          {STRINGS.daten.titel}
        </Text>
        <Text style={[stil.text, { color: farben.textSekundaer }]}>
          {dataset
            ? `${dataset.count} Anlagen, Stand ${(dataset.osmTimestamp ?? '').slice(0, 10) || STRINGS.allgemein.unbekannt}`
            : STRINGS.fehler.datensatzUnlesbar.titel}
        </Text>
        <Text style={[stil.klein, { color: farben.textLeise }]}>
          {STRINGS.daten.attribution} · {STRINGS.daten.lizenzName}
        </Text>
      </View>

      <Pressable
        onPress={() => void bestaetige()}
        disabled={!kannWeiter}
        style={(z) => [
          stil.knopf,
          {
            backgroundColor: kannWeiter ? farben.warn : farben.flaecheHoch,
            borderColor: kannWeiter ? farben.warn : farben.linie,
          },
          gedrueckt(z),
        ]}
        accessibilityRole="button"
        accessibilityState={{ disabled: !kannWeiter }}
        accessibilityLabel={STRINGS.allgemein.weiter}
      >
        <Text
          style={[
            stil.knopfText,
            { color: kannWeiter ? farben.aufWarn : farben.textInaktiv },
          ]}
        >
          {STRINGS.allgemein.weiter}
        </Text>
      </Pressable>
    </ScrollView>
  );
}

const stil = StyleSheet.create({
  inhalt: { padding: ABSTAND.RAND, paddingTop: SEITE.OBEN, gap: ABSTAND.RAND, paddingBottom: SEITE.UNTEN },
  titel: { fontSize: SCHRIFT.WARN_TITEL, letterSpacing: spur(SCHRIFT.WARN_TITEL), lineHeight: SCHRIFT.WARN_TITEL * ZEILENHOEHE.ENG, fontWeight: GEWICHT.FETT },
  karte: { borderWidth: LINIE.DUENN, borderRadius: RADIUS.M, padding: ABSTAND.L, gap: ABSTAND.M },
  kartenTitel: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.FETT },
  text: { fontSize: SCHRIFT.TEXT, lineHeight: SCHRIFT.TEXT * ZEILENHOEHE.TEXT },
  klein: { fontSize: SCHRIFT.KLEIN, lineHeight: SCHRIFT.KLEIN * ZEILENHOEHE.TEXT },
  schalterZeile: { flexDirection: 'row', alignItems: 'center', gap: ABSTAND.M, minHeight: TOUCH.MIN },
  knopf: {
    minHeight: TOUCH.MIN, borderWidth: LINIE.DICK, borderRadius: RADIUS.M,
    alignItems: 'center', justifyContent: 'center',
  },
  knopfText: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.FETT },
  knopfKlein: {
    minHeight: TOUCH.MIN, borderWidth: LINIE.DUENN, borderRadius: RADIUS.S,
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: ABSTAND.L,
  },
  knopfKleinText: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.MITTEL },
});
