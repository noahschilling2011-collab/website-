import { useEffect, useRef, useState } from 'react';
import { AppState, AppStateStatus, View } from 'react-native';
import { Stack, useRouter, useSegments } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { colors } from '../src/theme';
import { Title } from '../src/components/ui';
import { useSession } from '../src/store/useSession';

/** Full-screen brand cover shown whenever the app is not active — keeps account
 *  data out of the iOS/Android app-switcher snapshot. */
function PrivacyOverlay() {
  return (
    <View
      style={{
        position: 'absolute',
        top: 0, left: 0, right: 0, bottom: 0,
        backgroundColor: colors.bg,
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 1000,
      }}
    >
      <View style={{ width: 18, height: 18, borderRadius: 9, backgroundColor: colors.brand, marginBottom: 12 }} />
      <Title>HALT</Title>
    </View>
  );
}

/** Redirects between auth / lock / app based on session + lock state. */
function useAuthGate() {
  const bootstrapped = useSession((s) => s.bootstrapped);
  const session = useSession((s) => s.session);
  const locked = useSession((s) => s.locked);
  const segments = useSegments();
  const router = useRouter();

  useEffect(() => {
    if (!bootstrapped) return;
    const root = segments[0];
    const onAuth = root === 'auth';
    const onLock = root === 'lock';

    if (!session && !onAuth) {
      router.replace('/auth');
    } else if (session && locked && !onLock) {
      router.replace('/lock');
    } else if (session && !locked && onAuth) {
      router.replace('/');
    } else if (session && !locked && onLock) {
      router.replace('/(tabs)');
    }
  }, [bootstrapped, session, locked, segments, router]);
}

export default function RootLayout() {
  const bootstrap = useSession((s) => s.bootstrap);
  const lock = useSession((s) => s.lock);
  const [active, setActive] = useState(true);
  const appState = useRef(AppState.currentState);

  useEffect(() => {
    bootstrap();
    const sub = AppState.addEventListener('change', (next: AppStateStatus) => {
      // Lock as soon as the app leaves the foreground.
      if (appState.current === 'active' && next !== 'active') {
        lock();
      }
      appState.current = next;
      setActive(next === 'active');
    });
    return () => sub.remove();
  }, [bootstrap, lock]);

  useAuthGate();

  return (
    <SafeAreaProvider>
      <StatusBar style="light" />
      <Stack
        screenOptions={{
          headerStyle: { backgroundColor: colors.bg },
          headerTintColor: colors.text,
          headerTitleStyle: { fontWeight: '800' },
          contentStyle: { backgroundColor: colors.bg },
          headerShadowVisible: false,
        }}
      >
        <Stack.Screen name="auth" options={{ headerShown: false, gestureEnabled: false }} />
        <Stack.Screen name="lock" options={{ headerShown: false, gestureEnabled: false }} />
        <Stack.Screen name="index" options={{ headerShown: false }} />
        <Stack.Screen name="onboarding/protected-person" options={{ title: 'Wen schützt du?' }} />
        <Stack.Screen name="onboarding/trusted-circle" options={{ title: 'Wer wird gewarnt?' }} />
        <Stack.Screen name="onboarding/connect-bank" options={{ title: 'Konto verbinden' }} />
        <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
        <Stack.Screen name="alert/[id]" options={{ title: 'Warnung', presentation: 'modal' }} />
        <Stack.Screen name="check" options={{ title: 'Nachricht prüfen', presentation: 'modal' }} />
        <Stack.Screen name="pin-setup" options={{ title: 'App-Sperre', presentation: 'modal' }} />
      </Stack>
      {!active && <PrivacyOverlay />}
    </SafeAreaProvider>
  );
}
