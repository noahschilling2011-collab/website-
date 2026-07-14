import { View, ScrollView } from 'react-native';
import { useRouter } from 'expo-router';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Title, Body, Muted, Button } from '../src/components/ui';
import { colors, spacing } from '../src/theme';

export default function Welcome() {
  const router = useRouter();
  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: colors.bg }}>
      <ScrollView contentContainerStyle={{ padding: spacing(3), flexGrow: 1, justifyContent: 'space-between' }}>
        <View>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, marginBottom: spacing(5) }}>
            <View style={{ width: 14, height: 14, borderRadius: 7, backgroundColor: colors.brand }} />
            <Title style={{ fontSize: 22 }}>HALT</Title>
          </View>

          <Title style={{ fontSize: 34, lineHeight: 40, marginBottom: spacing(2) }}>
            Die Notbremse zwischen deinen Eltern und einem Betrug.
          </Title>
          <Body style={{ color: colors.muted, fontSize: 17 }}>
            HALT schlägt Alarm, wenn sich ihr Geld ungewöhnlich bewegt — ausgelöst vom Konto,
            nicht vom Zweifel des Opfers. Du entscheidest, ob etwas nicht stimmt. Nicht die App.
          </Body>

          <View style={{ marginTop: spacing(4), gap: spacing(2) }}>
            <Step n="1" title="Wen schützt du?" desc="Richte HALT für einen geliebten Menschen ein." />
            <Step n="2" title="Wer wird gewarnt?" desc="Bis zu drei Vertrauenspersonen im Alarm-Kreis." />
            <Step n="3" title="Konto verbinden" desc="Sicherer Lesezugriff über Open Banking (PSD2)." />
          </View>
        </View>

        <View style={{ marginTop: spacing(4), gap: spacing(1.5) }}>
          <Button title="Los geht's" onPress={() => router.push('/onboarding/protected-person')} />
          <Muted style={{ textAlign: 'center', fontSize: 13 }}>
            Für Angehörige. Die Kontrolle liegt bei dir — jederzeit widerrufbar.
          </Muted>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

function Step({ n, title, desc }: { n: string; title: string; desc: string }) {
  return (
    <View style={{ flexDirection: 'row', gap: 14, alignItems: 'flex-start' }}>
      <View
        style={{
          width: 32, height: 32, borderRadius: 9, backgroundColor: colors.card,
          borderWidth: 1, borderColor: colors.border, alignItems: 'center', justifyContent: 'center',
        }}
      >
        <Body style={{ fontWeight: '800', color: colors.brand }}>{n}</Body>
      </View>
      <View style={{ flex: 1 }}>
        <Body style={{ fontWeight: '700' }}>{title}</Body>
        <Muted style={{ fontSize: 14 }}>{desc}</Muted>
      </View>
    </View>
  );
}
