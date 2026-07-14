import { useState } from 'react';
import { ScrollView, TextInput, StyleSheet, View } from 'react-native';
import { Title, Muted, Body, Card, Button, RiskBadge } from '../src/components/ui';
import { colors, spacing, radius } from '../src/theme';
import { checkMessage, type MessageCheckResult } from '../src/lib/messageCheck';

export default function Check() {
  const [text, setText] = useState('');
  const [result, setResult] = useState<MessageCheckResult | null>(null);

  return (
    <ScrollView style={{ backgroundColor: colors.bg }} contentContainerStyle={{ padding: spacing(3) }}>
      <Title style={{ marginBottom: spacing(1) }}>Nachricht prüfen</Title>
      <Muted style={{ marginBottom: spacing(2) }}>
        Füg eine verdächtige SMS, E-Mail oder WhatsApp-Nachricht ein. HALT sucht nach typischen
        Betrugsmustern — und erklärt, was auffällt.
      </Muted>

      <TextInput
        value={text}
        onChangeText={(t) => {
          setText(t);
          setResult(null);
        }}
        placeholder="Nachricht hier einfügen…"
        placeholderTextColor={colors.muted}
        multiline
        style={styles.input}
      />

      <View style={{ height: spacing(2) }} />
      <Button title="Prüfen" disabled={!text.trim()} style={!text.trim() ? { opacity: 0.5 } : undefined} onPress={() => setResult(checkMessage(text))} />

      {result && (
        <Card style={{ marginTop: spacing(2), gap: spacing(1.5), borderColor: result.level === 'ok' ? colors.border : colors.brand }}>
          <RiskBadge level={result.level} />
          {result.level === 'ok' ? (
            <Body>Keine typischen Betrugsmuster gefunden. Trotzdem: bei Geldforderungen immer persönlich nachfragen.</Body>
          ) : (
            <>
              <Body style={{ fontWeight: '700' }}>Das ist aufgefallen:</Body>
              {result.reasons.map((r, i) => (
                <View key={i} style={{ flexDirection: 'row', gap: 10 }}>
                  <Body style={{ color: colors.brand }}>•</Body>
                  <Body style={{ flex: 1, fontSize: 15 }}>{r}</Body>
                </View>
              ))}
              <Muted style={{ fontSize: 14 }}>
                Im Zweifel: nicht antworten, nichts zahlen, und mit einer Vertrauensperson sprechen.
              </Muted>
            </>
          )}
        </Card>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  input: {
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius,
    padding: 16,
    fontSize: 16,
    color: colors.text,
    minHeight: 140,
    textAlignVertical: 'top',
  },
});
