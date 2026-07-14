import { useState } from 'react';
import { View, TextInput, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { Title, Muted, Button } from '../../src/components/ui';
import { useStore } from '../../src/store/useStore';
import { colors, spacing, radius } from '../../src/theme';

export default function ProtectedPerson() {
  const router = useRouter();
  const setPerson = useStore((s) => s.setPerson);
  const [name, setName] = useState('');

  return (
    <View style={{ flex: 1, backgroundColor: colors.bg, padding: spacing(3), justifyContent: 'space-between' }}>
      <View>
        <Title style={{ marginBottom: spacing(1) }}>Wen möchtest du schützen?</Title>
        <Muted style={{ marginBottom: spacing(3) }}>
          Der Name hilft dir nur, den Überblick zu behalten. Zum Beispiel „Mama" oder „Opa Werner".
        </Muted>
        <TextInput
          value={name}
          onChangeText={setName}
          placeholder="Name der Person"
          placeholderTextColor={colors.muted}
          style={styles.input}
          autoFocus
        />
      </View>
      <Button
        title="Weiter"
        disabled={!name.trim()}
        style={!name.trim() ? { opacity: 0.5 } : undefined}
        onPress={() => {
          setPerson(name.trim());
          router.push('/onboarding/trusted-circle');
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  input: {
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius,
    padding: 16,
    fontSize: 18,
    color: colors.text,
  },
});
