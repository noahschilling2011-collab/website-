import { useState } from 'react';
import { View, TextInput, StyleSheet, ScrollView, Pressable } from 'react-native';
import { useRouter } from 'expo-router';
import { Title, Muted, Body, Button, Card } from '../../src/components/ui';
import { useStore } from '../../src/store/useStore';
import { colors, spacing, radius } from '../../src/theme';

export default function TrustedCircle() {
  const router = useRouter();
  const contacts = useStore((s) => s.contacts);
  const addContact = useStore((s) => s.addContact);
  const removeContact = useStore((s) => s.removeContact);

  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [relation, setRelation] = useState('');

  const canAdd = name.trim() && phone.trim();

  return (
    <View style={{ flex: 1, backgroundColor: colors.bg }}>
      <ScrollView contentContainerStyle={{ padding: spacing(3) }}>
        <Title style={{ marginBottom: spacing(1) }}>Wer wird gewarnt?</Title>
        <Muted style={{ marginBottom: spacing(3) }}>
          Diese Personen bekommen sofort eine Nachricht — und bei einem echten Alarm einen Anruf.
          Am besten Menschen, die nah dran sind.
        </Muted>

        {contacts.map((c) => (
          <Card key={c.id} style={{ marginBottom: spacing(1.5), flexDirection: 'row', alignItems: 'center' }}>
            <View style={{ flex: 1 }}>
              <Body style={{ fontWeight: '700' }}>{c.name}</Body>
              <Muted style={{ fontSize: 14 }}>
                {c.phone}
                {c.relation ? ` · ${c.relation}` : ''}
              </Muted>
            </View>
            <Pressable onPress={() => removeContact(c.id)} hitSlop={10}>
              <Body style={{ color: colors.brand, fontWeight: '700' }}>Entfernen</Body>
            </Pressable>
          </Card>
        ))}

        <Card style={{ gap: spacing(1.5), marginTop: spacing(1) }}>
          <TextInput value={name} onChangeText={setName} placeholder="Name" placeholderTextColor={colors.muted} style={styles.input} />
          <TextInput value={phone} onChangeText={setPhone} placeholder="Telefonnummer" placeholderTextColor={colors.muted} keyboardType="phone-pad" style={styles.input} />
          <TextInput value={relation} onChangeText={setRelation} placeholder="Beziehung (optional, z. B. Tochter)" placeholderTextColor={colors.muted} style={styles.input} />
          <Button
            title="Vertrauensperson hinzufügen"
            variant="ghost"
            disabled={!canAdd}
            style={!canAdd ? { opacity: 0.5 } : undefined}
            onPress={() => {
              addContact({ name: name.trim(), phone: phone.trim(), relation: relation.trim() });
              setName('');
              setPhone('');
              setRelation('');
            }}
          />
        </Card>
      </ScrollView>

      <View style={{ padding: spacing(3), paddingTop: 0 }}>
        <Button
          title={contacts.length ? 'Weiter' : 'Mindestens eine Person hinzufügen'}
          disabled={contacts.length === 0}
          style={contacts.length === 0 ? { opacity: 0.5 } : undefined}
          onPress={() => router.push('/onboarding/connect-bank')}
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  input: {
    backgroundColor: colors.bgSoft,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius,
    padding: 14,
    fontSize: 16,
    color: colors.text,
  },
});
