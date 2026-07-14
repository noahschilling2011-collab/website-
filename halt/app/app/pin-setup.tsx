import { useState } from 'react';
import { View, StyleSheet, Pressable } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Title, Muted, Body } from '../src/components/ui';
import { setupPin } from '../src/lib/appLock';
import { useSession } from '../src/store/useSession';
import { validatePin } from '../src/lib/validation';
import { colors, spacing } from '../src/theme';

export default function PinSetup() {
  const router = useRouter();
  const refreshPinState = useSession((s) => s.refreshPinState);
  const [step, setStep] = useState<'enter' | 'confirm'>('enter');
  const [first, setFirst] = useState('');
  const [pin, setPin] = useState('');
  const [error, setError] = useState<string | null>(null);

  async function complete(fullPin: string) {
    if (step === 'enter') {
      const v = validatePin(fullPin);
      if (!v.ok) {
        setError(v.error!);
        setPin('');
        return;
      }
      setFirst(fullPin);
      setPin('');
      setStep('confirm');
      setError(null);
      return;
    }
    // confirm
    if (fullPin !== first) {
      setError('Die PINs stimmen nicht überein.');
      setPin('');
      setStep('enter');
      setFirst('');
      return;
    }
    await setupPin(fullPin);
    await refreshPinState();
    router.back();
  }

  function press(digit: string) {
    setError(null);
    if (pin.length >= 6) return;
    const next = pin + digit;
    setPin(next);
    if (next.length === 6) complete(next);
  }

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: colors.bg }}>
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: spacing(3) }}>
        <Title style={{ marginBottom: spacing(1) }}>
          {step === 'enter' ? 'App-Sperre einrichten' : 'PIN bestätigen'}
        </Title>
        <Muted style={{ marginBottom: spacing(4), textAlign: 'center' }}>
          {step === 'enter'
            ? 'Wähle einen 6-stelligen PIN. Er schützt die Daten auf diesem Gerät.'
            : 'Gib denselben PIN noch einmal ein.'}
        </Muted>

        <View style={{ flexDirection: 'row', gap: 14, marginBottom: spacing(3) }}>
          {Array.from({ length: 6 }).map((_, i) => (
            <View key={i} style={[styles.dot, { backgroundColor: i < pin.length ? colors.brand : 'transparent' }]} />
          ))}
        </View>

        {error && <Body style={{ color: colors.brand, marginBottom: spacing(2), textAlign: 'center' }}>{error}</Body>}

        <View style={styles.pad}>
          {['1', '2', '3', '4', '5', '6', '7', '8', '9'].map((d) => (
            <Key key={d} label={d} onPress={() => press(d)} />
          ))}
          <View style={styles.key} />
          <Key label="0" onPress={() => press('0')} />
          <View style={styles.key}>
            <Pressable onPress={() => setPin(pin.slice(0, -1))} style={styles.keyInner} hitSlop={8}>
              <Body style={{ fontSize: 20 }}>⌫</Body>
            </Pressable>
          </View>
        </View>
      </View>
    </SafeAreaView>
  );
}

function Key({ label, onPress }: { label: string; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [styles.key, pressed && { opacity: 0.6 }]}>
      <View style={styles.keyInner}>
        <Title style={{ fontSize: 26 }}>{label}</Title>
      </View>
    </Pressable>
  );
}

const KEY = 74;
const styles = StyleSheet.create({
  dot: { width: 14, height: 14, borderRadius: 7, borderWidth: 1.5, borderColor: colors.brand },
  pad: { width: KEY * 3 + 40, flexDirection: 'row', flexWrap: 'wrap', gap: 20, justifyContent: 'center' },
  key: { width: KEY, height: KEY, alignItems: 'center', justifyContent: 'center' },
  keyInner: {
    width: KEY, height: KEY, borderRadius: KEY / 2,
    alignItems: 'center', justifyContent: 'center',
    backgroundColor: colors.card, borderWidth: 1, borderColor: colors.border,
  },
});
