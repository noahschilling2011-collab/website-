import { ScrollView, View, Alert } from 'react-native';
import { useRouter } from 'expo-router';
import { Title, Muted, Body, Card, Button } from '../../src/components/ui';
import { useStore } from '../../src/store/useStore';
import { useSession } from '../../src/store/useSession';
import { clearPin } from '../../src/lib/appLock';
import { colors, spacing } from '../../src/theme';

export default function Settings() {
  const router = useRouter();
  const { person, contacts } = useStore();
  const session = useSession((s) => s.session);
  const pinEnabled = useSession((s) => s.pinEnabled);
  const refreshPinState = useSession((s) => s.refreshPinState);
  const signOut = useSession((s) => s.signOut);
  const wipe = useSession((s) => s.wipe);

  return (
    <ScrollView style={{ backgroundColor: colors.bg }} contentContainerStyle={{ padding: spacing(2.5) }}>
      <Title style={{ marginBottom: spacing(2) }}>Einstellungen</Title>

      <Muted style={{ marginBottom: spacing(1) }}>Geschützte Person</Muted>
      <Card style={{ marginBottom: spacing(2) }}>
        <Body style={{ fontWeight: '700' }}>{person?.name ?? '—'}</Body>
        <Muted style={{ marginTop: 4 }}>
          {person?.bankConnected ? 'Konto verbunden · Lesezugriff' : 'Konto nicht verbunden'}
        </Muted>
      </Card>

      <Muted style={{ marginBottom: spacing(1) }}>Alarm-Kreis ({contacts.length})</Muted>
      <Card style={{ marginBottom: spacing(2) }}>
        {contacts.length === 0 ? (
          <Muted>Keine Vertrauenspersonen.</Muted>
        ) : (
          contacts.map((c, i) => (
            <View key={c.id} style={{ paddingVertical: 8, borderTopWidth: i ? 1 : 0, borderTopColor: colors.border }}>
              <Body style={{ fontWeight: '600' }}>{c.name}</Body>
              <Muted style={{ fontSize: 14 }}>
                {c.phone}
                {c.relation ? ` · ${c.relation}` : ''}
              </Muted>
            </View>
          ))
        )}
      </Card>

      <Button title="Alarm-Kreis bearbeiten" variant="ghost" onPress={() => router.push('/onboarding/trusted-circle')} />

      <View style={{ height: spacing(3) }} />
      <Muted style={{ marginBottom: spacing(1) }}>Sicherheit</Muted>
      <Card style={{ marginBottom: spacing(2), gap: spacing(1.5) }}>
        <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
          <View style={{ flex: 1 }}>
            <Body style={{ fontWeight: '600' }}>App-Sperre (PIN + Biometrie)</Body>
            <Muted style={{ fontSize: 14 }}>{pinEnabled ? 'Aktiv' : 'Nicht eingerichtet'}</Muted>
          </View>
        </View>
        {pinEnabled ? (
          <Button
            title="App-Sperre entfernen"
            variant="ghost"
            onPress={() =>
              Alert.alert('App-Sperre entfernen?', 'Die Daten sind dann nicht mehr per PIN geschützt.', [
                { text: 'Abbrechen', style: 'cancel' },
                {
                  text: 'Entfernen',
                  style: 'destructive',
                  onPress: async () => {
                    await clearPin();
                    await refreshPinState();
                  },
                },
              ])
            }
          />
        ) : (
          <Button title="App-Sperre einrichten" onPress={() => router.push('/pin-setup')} />
        )}
      </Card>

      <Muted style={{ marginBottom: spacing(1) }}>Konto</Muted>
      <Card style={{ marginBottom: spacing(2) }}>
        <Body style={{ fontWeight: '600' }}>{session?.email ?? '—'}</Body>
        <Muted style={{ fontSize: 14, marginBottom: spacing(1.5) }}>Angemeldet</Muted>
        <Button title="Abmelden" variant="ghost" onPress={signOut} />
      </Card>

      <Card style={{ borderStyle: 'dashed', marginBottom: spacing(2) }}>
        <Body style={{ fontWeight: '700', marginBottom: 6 }}>Datenschutz</Body>
        <Muted style={{ fontSize: 14 }}>
          HALT sieht nur Kontoumsätze, nie das Geld selbst. Verschlüsselt, in der EU verarbeitet,
          Einwilligung jederzeit widerrufbar.
        </Muted>
      </Card>

      <Button
        title="Konto & alle Daten löschen"
        variant="ghost"
        style={{ borderColor: colors.brand }}
        onPress={() =>
          Alert.alert(
            'Alles löschen?',
            'Konto, PIN und alle lokalen Daten werden unwiderruflich entfernt.',
            [
              { text: 'Abbrechen', style: 'cancel' },
              { text: 'Endgültig löschen', style: 'destructive', onPress: () => wipe() },
            ],
          )
        }
      />
      <View style={{ height: spacing(3) }} />
    </ScrollView>
  );
}
