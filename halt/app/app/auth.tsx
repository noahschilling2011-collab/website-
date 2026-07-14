import { useState } from 'react';
import { View, TextInput, StyleSheet, ScrollView, Pressable, KeyboardAvoidingView, Platform } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Title, Muted, Body, Button } from '../src/components/ui';
import { useSession } from '../src/store/useSession';
import { validateEmail, validatePassword } from '../src/lib/validation';
import { colors, spacing, radius } from '../src/theme';

export default function Auth() {
  const [mode, setMode] = useState<'signin' | 'signup'>('signin');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const signIn = useSession((s) => s.signIn);
  const signUp = useSession((s) => s.signUp);

  const isSignup = mode === 'signup';

  async function submit() {
    setError(null);
    const e = validateEmail(email);
    if (!e.ok) return setError(e.error!);
    if (isSignup) {
      const p = validatePassword(password);
      if (!p.ok) return setError(p.error!);
    } else if (!password) {
      return setError('Bitte Passwort eingeben.');
    }
    setBusy(true);
    const err = isSignup ? await signUp(email, password) : await signIn(email, password);
    setBusy(false);
    if (err) setError(err);
  }

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: colors.bg }}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1 }}>
        <ScrollView contentContainerStyle={{ padding: spacing(3), flexGrow: 1, justifyContent: 'center' }}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, marginBottom: spacing(4) }}>
            <View style={{ width: 14, height: 14, borderRadius: 7, backgroundColor: colors.brand }} />
            <Title style={{ fontSize: 22 }}>HALT</Title>
          </View>

          <Title style={{ marginBottom: spacing(1) }}>
            {isSignup ? 'Konto erstellen' : 'Willkommen zurück'}
          </Title>
          <Muted style={{ marginBottom: spacing(3) }}>
            {isSignup
              ? 'Deine Daten sind verschlüsselt und liegen in der EU.'
              : 'Melde dich an, um fortzufahren.'}
          </Muted>

          <TextInput
            value={email}
            onChangeText={setEmail}
            placeholder="E-Mail"
            placeholderTextColor={colors.muted}
            keyboardType="email-address"
            autoCapitalize="none"
            autoComplete="email"
            style={styles.input}
          />
          <TextInput
            value={password}
            onChangeText={setPassword}
            placeholder={isSignup ? 'Passwort (mind. 10 Zeichen)' : 'Passwort'}
            placeholderTextColor={colors.muted}
            secureTextEntry
            autoCapitalize="none"
            autoComplete={isSignup ? 'new-password' : 'current-password'}
            style={[styles.input, { marginTop: spacing(1.5) }]}
          />

          {error && <Body style={{ color: colors.brand, marginTop: spacing(1.5) }}>{error}</Body>}

          <View style={{ height: spacing(3) }} />
          <Button title={isSignup ? 'Registrieren' : 'Anmelden'} loading={busy} onPress={submit} />

          <Pressable
            onPress={() => {
              setMode(isSignup ? 'signin' : 'signup');
              setError(null);
            }}
            style={{ marginTop: spacing(2.5), alignItems: 'center' }}
          >
            <Muted>
              {isSignup ? 'Schon ein Konto? ' : 'Noch kein Konto? '}
              <Body style={{ color: colors.brand, fontWeight: '700' }}>
                {isSignup ? 'Anmelden' : 'Registrieren'}
              </Body>
            </Muted>
          </Pressable>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
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
  },
});
