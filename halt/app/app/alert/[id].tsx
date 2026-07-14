import { ScrollView, View, Linking } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Title, Muted, Body, Card, Button, RiskBadge } from '../../src/components/ui';
import { useStore } from '../../src/store/useStore';
import { colors, spacing, levelColor } from '../../src/theme';

export default function AlertDetail() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const { transactions, assessments, contacts, resolveAlert } = useStore();

  const tx = transactions.find((t) => t.id === id);
  const assessment = assessments.find((a) => a.transactionId === id);

  if (!tx || !assessment) {
    return (
      <View style={{ flex: 1, backgroundColor: colors.bg, padding: spacing(3) }}>
        <Muted>Diese Bewegung wurde nicht gefunden.</Muted>
      </View>
    );
  }

  const c = levelColor(assessment.level);
  const firstContact = contacts[0];

  return (
    <ScrollView style={{ backgroundColor: colors.bg }} contentContainerStyle={{ padding: spacing(3) }}>
      <View style={{ alignItems: 'center', marginBottom: spacing(3) }}>
        <RiskBadge level={assessment.level} />
        <Title style={{ fontSize: 40, marginTop: spacing(2), color: c }}>
          {tx.amount.toLocaleString('de-DE')} €
        </Title>
        <Body style={{ fontSize: 18, marginTop: 4 }}>an {tx.payeeName}</Body>
        <Muted style={{ marginTop: 4 }}>
          {new Date(tx.date).toLocaleString('de-DE')} · {tx.category}
        </Muted>
      </View>

      <Muted style={{ marginBottom: spacing(1) }}>Warum HALT gewarnt hat</Muted>
      <Card style={{ marginBottom: spacing(2), gap: spacing(1.5) }}>
        {assessment.signals.map((s, i) => (
          <View key={i} style={{ flexDirection: 'row', gap: 10, alignItems: 'flex-start' }}>
            <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: c, marginTop: 7 }} />
            <Body style={{ flex: 1, fontSize: 15 }}>{s.message}</Body>
          </View>
        ))}
      </Card>

      <Muted style={{ marginBottom: spacing(1) }}>Du entscheidest</Muted>
      <Card style={{ marginBottom: spacing(2) }}>
        <Muted style={{ fontSize: 14, marginBottom: spacing(1.5) }}>
          HALT sagt nicht, ob das Betrug ist — das kannst nur du beurteilen. Ruf am besten kurz an
          und frag nach, bevor Geld unwiderruflich weg ist.
        </Muted>
        {firstContact && (
          <Button
            title={`${firstContact.name} anrufen`}
            onPress={() => Linking.openURL(`tel:${firstContact.phone}`)}
            style={{ marginBottom: spacing(1) }}
          />
        )}
      </Card>

      <View style={{ gap: spacing(1) }}>
        <Button
          title="Ich kümmere mich darum"
          variant="ghost"
          onPress={() => {
            resolveAlert(tx.id, 'handled');
            router.back();
          }}
        />
        <Button
          title="Alles in Ordnung — war bekannt"
          variant="ghost"
          onPress={() => {
            resolveAlert(tx.id, 'dismissed');
            router.back();
          }}
        />
      </View>
    </ScrollView>
  );
}
