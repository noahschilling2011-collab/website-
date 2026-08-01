/**
 * Rechtliches — die Dokumente und die eigenen Daten an einer Stelle.
 *
 * WARUM EIN EIGENER BEREICH
 *
 * Die Angaben waren vorher über Info- und Einstellungs-Screen verteilt, und
 * drei fehlten ganz. Beide App-Stores erwarten sie auffindbar; ein Prüfer,
 * der die Datenschutzerklärung sucht und nicht findet, lehnt ab.
 *
 * WARUM DIE TEXTE IN DER APP LIEGEN UND NICHT VERLINKT SIND
 *
 * Weil die App keine Netzwerkverbindung herstellt. Ein Link auf eine Website
 * wäre ausgerechnet in der Datenschutzerklärung der einzige Ort, an dem die
 * App den Nutzer ins Netz schickt — und lesbar wäre sie im Funkloch dann
 * auch nicht. Die Fassung unter einer Adresse gibt es zusätzlich, weil die
 * Stores sie verlangen; erzeugt wird sie aus derselben Quelle
 * (scripts/make-legal-docs.ts).
 */
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Share, Text, View } from 'react-native';

import { STRINGS } from '../strings';
import {
  DOKUMENTE,
  hatLuecken,
  type Dokument,
} from '../rechtstexte';
import {
  ABSTAND, GEWICHT, LINIE, RADIUS, SCHRIFT, SEITE, SPUR, TOUCH, ZEILENHOEHE,
  gedrueckt, palette, spur, type ThemeMode,
} from './theme';
import { errorLog } from '../core/log';
import { useApp } from '../state/store';
import { fahrtprotokollAlsCsv, fahrtprotokollAnzahl } from '../location/task';

type Props = { mode: ThemeMode; onZurueck: () => void };

export default function RechtlichesScreen({ mode, onZurueck }: Props) {
  const farben = palette(mode);
  const [offen, setOffen] = useState<Dokument | null>(null);
  const fahrtprotokollAn = useApp((s) => s.settings.fahrtprotokoll);
  const setze = useApp((s) => s.setzeEinstellung);

  /**
   * Die eigenen Daten weitergeben.
   *
   * Das ist der Datenexport im Sinne von Art. 20 DSGVO — auch wenn er hier
   * fast leer ausfällt: Ausser den Einstellungen, dem Fehlerprotokoll und
   * (falls eingeschaltet) dem Fahrtprotokoll gibt es nichts. Genau das soll
   * der Nutzer sehen können.
   */
  function teileDaten(): void {
    try {
      const teile = [
        `Static — Datenexport, ${new Date().toISOString().slice(0, 10)}`,
        '',
        'Diese App speichert ausschliesslich auf dem Geraet und uebertraegt',
        'nichts. Der folgende Text ist alles, was sie ueber dich vorhaelt.',
        '',
        '--- Einstellungen ---',
        JSON.stringify(useApp.getState().settings, null, 2),
        '',
        '--- Fehlerprotokoll ---',
        errorLog.toText(),
      ];

      if (fahrtprotokollAn && fahrtprotokollAnzahl() > 0) {
        teile.push('', '--- Fahrtprotokoll ---', fahrtprotokollAlsCsv());
      } else {
        teile.push('', '--- Fahrtprotokoll ---', '(nicht eingeschaltet, keine Aufzeichnung)');
      }

      void Share.share({ message: teile.join('\n'), title: STRINGS.rechtliches.datenExport })
        .catch((err) => errorLog.error('start', 'Datenexport konnte nicht geteilt werden', err));
    } catch (err) {
      errorLog.error('start', 'Datenexport konnte nicht erzeugt werden', err);
    }
  }

  /**
   * Alles löschen, was auf dem Gerät liegt.
   *
   * Kein Konto, also nichts zu kündigen — was hier gelöscht wird, sind die
   * Einstellungen, das Fehlerprotokoll und das Fahrtprotokoll. Der
   * Rechtshinweis bleibt bestätigt: Ihn zurückzusetzen würde den Nutzer beim
   * nächsten Start durch das Onboarding schicken, und das ist keine Löschung
   * von Daten, sondern eine Belästigung.
   */
  function loescheAlles(): void {
    void (async () => {
      try {
        // Zuerst den Fahrtenschreiber ausschalten: setzeSettings() im Task
        // löscht dabei die laufende Aufzeichnung. Andersherum bliebe sie im
        // Arbeitsspeicher stehen.
        if (fahrtprotokollAn) await setze('fahrtprotokoll', false);
        await useApp.getState().loescheAlleDaten();
      } catch (err) {
        errorLog.error('einstellungen', 'Loeschen fehlgeschlagen', err);
      }
    })();
  }

  // --- Ein einzelnes Dokument ---------------------------------------------

  if (offen !== null) {
    return (
      <ScrollView
        style={{ backgroundColor: farben.hintergrund }}
        contentContainerStyle={stil.inhalt}
      >
        <Text style={[stil.titel, { color: farben.text }]}>{offen.titel}</Text>
        <Text style={[stil.klein, { color: farben.textLeise }]}>
          {`${STRINGS.rechtliches.stand}: ${offen.stand}`}
        </Text>

        {hatLuecken(offen) && (
          <View style={[stil.karte, { borderColor: farben.warn, backgroundColor: farben.warnGedaempft }]}>
            <Text style={[stil.text, { color: farben.warn }]}>
              {STRINGS.rechtliches.unvollstaendig}
            </Text>
          </View>
        )}

        {offen.abschnitte.map((abschnitt) => (
          <View key={abschnitt.titel} style={stil.abschnitt}>
            <Text style={[stil.abschnittTitel, { color: farben.text }]}>
              {abschnitt.titel}
            </Text>
            {abschnitt.absaetze.map((absatz, i) => (
              <Text key={i} style={[stil.text, { color: farben.textSekundaer }]} selectable>
                {absatz}
              </Text>
            ))}
          </View>
        ))}

        <Pressable
          onPress={() => setOffen(null)}
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

  // --- Die Übersicht -------------------------------------------------------

  return (
    <ScrollView
      style={{ backgroundColor: farben.hintergrund }}
      contentContainerStyle={stil.inhalt}
    >
      <Text style={[stil.titel, { color: farben.text }]}>
        {STRINGS.rechtliches.titel}
      </Text>

      {DOKUMENTE.map((dokument) => (
        <Pressable
          key={dokument.titel}
          onPress={() => setOffen(dokument)}
          style={(z) => [stil.zeile, { borderColor: farben.linie }, gedrueckt(z)]}
          accessibilityRole="button"
          accessibilityLabel={dokument.titel}
        >
          <View style={stil.zeileText}>
            <Text style={[stil.label, { color: farben.text }]}>{dokument.titel}</Text>
            <Text style={[stil.hilfe, { color: farben.textLeise }]}>
              {dokument.vorspann}
            </Text>
          </View>
          {hatLuecken(dokument) && (
            <Text style={[stil.hilfe, { color: farben.warn }]}>
              {STRINGS.rechtliches.luecke}
            </Text>
          )}
        </Pressable>
      ))}

      {/* Meine Daten. Ohne Konto bleibt davon wenig — und genau das ist die
          Aussage, die der Nutzer hier sehen soll. */}
      <Text style={[stil.gruppe, { color: farben.textLeise }]}>
        {STRINGS.rechtliches.meineDaten}
      </Text>

      <View style={[stil.karte, { borderColor: farben.linie, backgroundColor: farben.flaeche }]}>
        <Text style={[stil.hilfe, { color: farben.textSekundaer }]}>
          {STRINGS.rechtliches.meineDatenHilfe}
        </Text>

        <Pressable
          onPress={teileDaten}
          style={(z) => [stil.link, { borderColor: farben.linie }, gedrueckt(z)]}
          accessibilityRole="button"
          accessibilityLabel={STRINGS.rechtliches.datenExport}
        >
          <Text style={[stil.linkText, { color: farben.text }]}>
            {STRINGS.rechtliches.datenExport}
          </Text>
        </Pressable>

        <Pressable
          onPress={loescheAlles}
          style={(z) => [stil.link, { borderColor: farben.warn }, gedrueckt(z)]}
          accessibilityRole="button"
          accessibilityLabel={STRINGS.rechtliches.datenLoeschen}
        >
          <Text style={[stil.linkText, { color: farben.warn }]}>
            {STRINGS.rechtliches.datenLoeschen}
          </Text>
        </Pressable>

        <Text style={[stil.klein, { color: farben.textLeise }]}>
          {STRINGS.rechtliches.keinKonto}
        </Text>
      </View>

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
  inhalt: { padding: ABSTAND.RAND, paddingTop: SEITE.OBEN, gap: ABSTAND.M, paddingBottom: SEITE.UNTEN },
  titel: { fontSize: SCHRIFT.WARN_TITEL, letterSpacing: spur(SCHRIFT.WARN_TITEL), lineHeight: SCHRIFT.WARN_TITEL * ZEILENHOEHE.ENG, fontWeight: GEWICHT.FETT, marginBottom: ABSTAND.S },
  gruppe: {
    fontSize: SCHRIFT.LABEL, textTransform: 'uppercase', letterSpacing: SPUR.VERSALIEN, marginTop: ABSTAND.RAND,
  },
  zeile: {
    flexDirection: 'row', alignItems: 'center', gap: ABSTAND.M,
    minHeight: TOUCH.MIN, borderBottomWidth: LINIE.DUENN, paddingVertical: ABSTAND.M,
  },
  zeileText: { flex: 1, gap: ABSTAND.XS },
  label: { fontSize: SCHRIFT.TEXT },
  hilfe: { fontSize: SCHRIFT.KLEIN, lineHeight: SCHRIFT.KLEIN * ZEILENHOEHE.TEXT },
  abschnitt: { gap: ABSTAND.S, marginTop: ABSTAND.L },
  abschnittTitel: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.FETT },
  text: { fontSize: SCHRIFT.TEXT, lineHeight: SCHRIFT.TEXT * ZEILENHOEHE.TEXT },
  klein: { fontSize: SCHRIFT.KLEIN, lineHeight: SCHRIFT.KLEIN * ZEILENHOEHE.TEXT },
  karte: { borderWidth: LINIE.DUENN, borderRadius: RADIUS.M, padding: ABSTAND.L, gap: ABSTAND.M },
  link: {
    minHeight: TOUCH.MIN, borderWidth: LINIE.DUENN, borderRadius: RADIUS.S,
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: ABSTAND.M,
  },
  linkText: { fontSize: SCHRIFT.TEXT },
  knopf: {
    marginTop: ABSTAND.XL, minHeight: TOUCH.MIN, borderWidth: LINIE.DUENN, borderRadius: RADIUS.M,
    alignItems: 'center', justifyContent: 'center',
  },
  knopfText: { fontSize: SCHRIFT.TEXT, fontWeight: GEWICHT.MITTEL },
});
