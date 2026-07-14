import { View, ScrollView } from 'react-native';
import { useRouter } from 'expo-router';
import { Title, Muted, Body, Button, Card } from '../../src/components/ui';
import { useStore } from '../../src/store/useStore';
import { colors, spacing } from '../../src/theme';

export default function ConnectBank() {
  const router = useRouter();
  const loading = useStore((s) => s.loading);
  const connectAndScan = useStore((s) => s.connectAndScan);
  const person = useStore((s) => s.person);

  return (
    <View style={{ flex: 1, backgroundColor: colors.bg }}>
      <ScrollView contentContainerStyle={{ padding: spacing(3) }}>
        <Title style={{ marginBottom: spacing(1) }}>Konto sicher verbinden</Title>
        <Muted style={{ marginBottom: spacing(3) }}>
          {person?.name ?? 'Die Person'} gibt einmalig ihre Einwilligung über einen lizenzierten
          Open-Banking-Zugang. HALT sieht nur die Umsätze — nie das Geld selbst.
        </Muted>

        <Card style={{ gap: spacing(1.5), marginBottom: spacing(2) }}>
          <Point text="Nur Lesezugriff auf Kontoumsätze" />
          <Point text="Kein Zugriff auf das Geld, keine Überweisungen möglich" />
          <Point text="Einwilligung jederzeit widerrufbar" />
          <Point text="Verarbeitung in der EU (DSGVO)" />
        </Card>

        <Card style={{ borderStyle: 'dashed' }}>
          <Muted style={{ fontSize: 13 }}>
            Demo-Modus: Diese Verbindung ist simuliert. In der echten App läuft sie über einen
            lizenzierten Anbieter (z. B. Tink / finAPI). HALT hält keine eigene Banklizenz.
          </Muted>
        </Card>
      </ScrollView>

      <View style={{ padding: spacing(3), paddingTop: 0 }}>
        <Button
          title={loading ? 'Verbinde…' : 'Konto verbinden & prüfen'}
          loading={loading}
          onPress={async () => {
            await connectAndScan();
            router.replace('/(tabs)');
          }}
        />
      </View>
    </View>
  );
}

function Point({ text }: { text: string }) {
  return (
    <View style={{ flexDirection: 'row', gap: 10, alignItems: 'flex-start' }}>
      <Body style={{ color: colors.accent, fontWeight: '800' }}>✓</Body>
      <Body style={{ flex: 1, fontSize: 15 }}>{text}</Body>
    </View>
  );
}
