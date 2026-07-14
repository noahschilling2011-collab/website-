import { ScrollView, View, Pressable } from 'react-native';
import { useRouter } from 'expo-router';
import { Title, Muted, Body, Card, RiskBadge } from '../../src/components/ui';
import { useStore } from '../../src/store/useStore';
import { colors, spacing } from '../../src/theme';

export default function Alerts() {
  const router = useRouter();
  const alerts = useStore((s) => s.alerts);

  const sorted = [...alerts].sort((a, b) => b.assessment.score - a.assessment.score);

  return (
    <ScrollView style={{ backgroundColor: colors.bg }} contentContainerStyle={{ padding: spacing(2.5) }}>
      <Title style={{ marginBottom: spacing(2) }}>Warnungen</Title>

      {sorted.length === 0 && (
        <Card>
          <Body style={{ fontWeight: '700', marginBottom: 4 }}>Alles ruhig.</Body>
          <Muted>Keine ungewöhnlichen Bewegungen. Genau so soll es sein.</Muted>
        </Card>
      )}

      {sorted.map((a) => (
        <Pressable key={a.transaction.id} onPress={() => router.push(`/alert/${a.transaction.id}`)}>
          <Card style={{ marginBottom: spacing(1.5), opacity: a.resolution ? 0.55 : 1 }}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
              <RiskBadge level={a.assessment.level} />
              <Muted style={{ fontSize: 13 }}>Score {a.assessment.score}</Muted>
            </View>
            <Body style={{ fontWeight: '700' }}>
              {a.transaction.amount.toLocaleString('de-DE')} € an {a.transaction.payeeName}
            </Body>
            <Muted style={{ marginTop: 4 }}>{a.assessment.signals[0]?.message}</Muted>
            {a.resolution && (
              <Muted style={{ marginTop: 8, color: colors.accent }}>
                {a.resolution === 'handled' ? '✓ Erledigt' : '✓ Als unkritisch markiert'}
              </Muted>
            )}
          </Card>
        </Pressable>
      ))}
    </ScrollView>
  );
}
