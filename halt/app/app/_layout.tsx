import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { colors } from '../src/theme';

export default function RootLayout() {
  return (
    <>
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
        <Stack.Screen name="index" options={{ headerShown: false }} />
        <Stack.Screen name="onboarding/protected-person" options={{ title: 'Wen schützt du?' }} />
        <Stack.Screen name="onboarding/trusted-circle" options={{ title: 'Wer wird gewarnt?' }} />
        <Stack.Screen name="onboarding/connect-bank" options={{ title: 'Konto verbinden' }} />
        <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
        <Stack.Screen name="alert/[id]" options={{ title: 'Warnung', presentation: 'modal' }} />
        <Stack.Screen name="check" options={{ title: 'Nachricht prüfen', presentation: 'modal' }} />
      </Stack>
    </>
  );
}
