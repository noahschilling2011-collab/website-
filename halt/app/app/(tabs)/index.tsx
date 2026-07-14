import { View, ScrollView, RefreshControl } from 'react-native';
import { useRouter } from 'expo-router';
import { Title, Muted, Body, Card, TransactionRow, Button } from '../../src/components/ui';
import { useStore } from '../../src/store/useStore';
import { colors, spacing } from '../../src/theme';

export default function Activity() {
  const router = useRouter();
  const { transactions, assessments, person, loading, connectAndScan } = useStore();

  const byId = new Map(assessments.map((a) => [a.transactionId, a]));
  // Newest first
  const sorted = [...transactions].sort(
    (a, b) => new Date(b.date).getTime() - new Date(a.date).getTime(),
  );
  const openAlerts = useStore((s) => s.alerts.filter((a) => !a.resolution).length);

  return (
    <ScrollView
      style={{ backgroundColor: colors.bg }}
      contentContainerStyle={{ padding: spacing(2.5) }}
      refreshControl={<RefreshControl refreshing={loading} onRefresh={() => connectAndScan()} tintColor={colors.muted} />}
    >
      <Muted style={{ fontSize: 14 }}>Geschützt</Muted>
      <Title style={{ marginBottom: spacing(2) }}>{person?.name ?? 'Konto'}</Title>

      {openAlerts > 0 && (
        <Card style={{ borderColor: colors.brand, marginBottom: spacing(2) }}>
          <Body style={{ fontWeight: '700', color: colors.brand }}>
            {openAlerts} offene {openAlerts === 1 ? 'Warnung' : 'Warnungen'}
          </Body>
          <Muted style={{ marginTop: 4, marginBottom: spacing(1.5) }}>
            Ungewöhnliche Bewegungen, die deine Aufmerksamkeit brauchen.
          </Muted>
          <Button title="Warnungen ansehen" variant="ghost" onPress={() => router.push('/(tabs)/alerts')} />
        </Card>
      )}

      <Card style={{ padding: 0, paddingHorizontal: spacing(2) }}>
        {sorted.length === 0 ? (
          <View style={{ padding: spacing(3), alignItems: 'center' }}>
            <Muted>Noch keine Bewegungen geladen.</Muted>
            <View style={{ height: spacing(1.5) }} />
            <Button title="Jetzt prüfen" onPress={() => connectAndScan()} loading={loading} />
          </View>
        ) : (
          sorted.map((tx) => (
            <TransactionRow
              key={tx.id}
              tx={tx}
              assessment={byId.get(tx.id)}
              onPress={() =>
                byId.get(tx.id)?.level !== 'ok' ? router.push(`/alert/${tx.id}`) : undefined
              }
            />
          ))
        )}
      </Card>

      <View style={{ height: spacing(2) }} />
      <Button title="Verdächtige Nachricht prüfen" variant="ghost" onPress={() => router.push('/check')} />
    </ScrollView>
  );
}
