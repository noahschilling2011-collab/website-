import { useEffect, useState, useCallback } from 'react';
import { View, StyleSheet, Pressable } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Title, Muted, Body } from '../src/components/ui';
import { useSession } from '../src/store/useSession';
import { verifyPin, authenticateBiometric, biometricInfo, currentGate } from '../src/lib/appLock';
import { colors, spacing } from '../src/theme';

const now = () => new Date().getTime();

export default function Lock() {
  const unlock = useSession((s) => s.unlock);
  const wipe = useSession((s) => s.wipe);
  const [pin, setPin] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [waitMsg, setWaitMsg] = useState<string | null>(null);
  const [canBiometric, setCanBiometric] = useState(false);

  const tryBiometric = useCallback(async () => {
    if (await authenticateBiometric()) unlock();
  }, [unlock]);

  useEffect(() => {
    (async () => {
      const info = await biometricInfo();
      const gate = await currentGate(now());
      setCanBiometric(info.available && info.enrolled && gate.allowed);
      if (info.available && info.enrolled && gate.allowed) tryBiometric();
    })();
  }, [tryBiometric]);

  async function submit(fullPin: string) {
    const res = await verifyPin(fullPin, now());
    if (res.ok) {
      unlock();
      return;
    }
    setPin('');
    if (res.gate.mustReset) {
      setError('Zu viele Fehlversuche. Bitte melde dich erneut mit deinem Passwort an.');
      await wipe();
      return;
    }
    if (!res.gate.allowed && res.gate.remainingMs > 0) {
      const secs = Math.ceil(res.gate.remainingMs / 1000);
      setWaitMsg(`Zu viele Versuche. Bitte ${secs}s warten.`);
      setError(null);
    } else {
      setError('Falscher PIN.');
    }
  }

  function press(digit: string) {
    setError(null);
    if (pin.length >= 6) return;
    const next = pin + digit;
    setPin(next);
    if (next.length === 6) submit(next);
  }

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: colors.bg }}>
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: spacing(3) }}>
        <View style={{ width: 14, height: 14, borderRadius: 7, backgroundColor: colors.brand, marginBottom: spacing(3) }} />
        <Title style={{ marginBottom: spacing(1) }}>HALT entsperren</Title>
        <Muted style={{ marginBottom: spacing(4) }}>Gib deinen 6-stelligen PIN ein.</Muted>

        <View style={{ flexDirection: 'row', gap: 14, marginBottom: spacing(3) }}>
          {Array.from({ length: 6 }).map((_, i) => (
            <View
              key={i}
              style={[styles.pinDot, { backgroundColor: i < pin.length ? colors.brand : 'transparent' }]}
            />
          ))}
        </View>

        {error && <Body style={{ color: colors.brand, marginBottom: spacing(2) }}>{error}</Body>}
        {waitMsg && <Body style={{ color: colors.watch, marginBottom: spacing(2) }}>{waitMsg}</Body>}

        <View style={styles.pad}>
          {['1', '2', '3', '4', '5', '6', '7', '8', '9'].map((d) => (
            <Key key={d} label={d} onPress={() => press(d)} />
          ))}
          <View style={styles.key}>
            {canBiometric ? (
              <Pressable onPress={tryBiometric} style={styles.keyInner} hitSlop={8}>
                <Body style={{ fontSize: 24 }}>☑</Body>
              </Pressable>
            ) : null}
          </View>
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
  pinDot: {
    width: 14, height: 14, borderRadius: 7,
    borderWidth: 1.5, borderColor: colors.brand,
  },
  pad: { width: KEY * 3 + 40, flexDirection: 'row', flexWrap: 'wrap', gap: 20, justifyContent: 'center' },
  key: { width: KEY, height: KEY, alignItems: 'center', justifyContent: 'center' },
  keyInner: {
    width: KEY, height: KEY, borderRadius: KEY / 2,
    alignItems: 'center', justifyContent: 'center',
    backgroundColor: colors.card, borderWidth: 1, borderColor: colors.border,
  },
});
