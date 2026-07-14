import { ScrollView, View } from 'react-native';
import { useRouter } from 'expo-router';
import { Title, Muted, Body, Card, Button } from '../../src/components/ui';
import { useStore } from '../../src/store/useStore';
import { colors, spacing } from '../../src/theme';

export default function Settings() {
  const router = useRouter();
  const { person, contacts } = useStore();

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
      <Card style={{ borderStyle: 'dashed' }}>
        <Body style={{ fontWeight: '700', marginBottom: 6 }}>Datenschutz</Body>
        <Muted style={{ fontSize: 14 }}>
          HALT sieht nur Kontoumsätze, nie das Geld selbst. Die Einwilligung ist jederzeit
          widerrufbar. Verarbeitung in der EU.
        </Muted>
      </Card>
    </ScrollView>
  );
}
