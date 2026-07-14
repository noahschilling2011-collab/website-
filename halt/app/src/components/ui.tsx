// Small shared UI primitives. One file to keep the MVP compact.

import React from 'react';
import {
  Text,
  TextProps,
  Pressable,
  PressableProps,
  View,
  ViewProps,
  StyleSheet,
  ActivityIndicator,
} from 'react-native';
import { colors, radius, levelColor, levelLabel } from '../theme';
import type { RiskLevel, Transaction, Assessment } from '../types';

export function Title({ style, ...p }: TextProps) {
  return <Text {...p} style={[styles.title, style]} />;
}
export function Subtitle({ style, ...p }: TextProps) {
  return <Text {...p} style={[styles.subtitle, style]} />;
}
export function Body({ style, ...p }: TextProps) {
  return <Text {...p} style={[styles.body, style]} />;
}
export function Muted({ style, ...p }: TextProps) {
  return <Text {...p} style={[styles.muted, style]} />;
}

export function Card({ style, ...p }: ViewProps) {
  return <View {...p} style={[styles.card, style]} />;
}

export function Button({
  title,
  variant = 'primary',
  loading,
  style,
  ...p
}: PressableProps & { title: string; variant?: 'primary' | 'ghost'; loading?: boolean }) {
  const isPrimary = variant === 'primary';
  return (
    <Pressable
      {...p}
      style={({ pressed }) => [
        styles.btn,
        isPrimary ? styles.btnPrimary : styles.btnGhost,
        pressed && { opacity: 0.85 },
        style as object,
      ]}
    >
      {loading ? (
        <ActivityIndicator color={isPrimary ? '#fff' : colors.text} />
      ) : (
        <Text style={[styles.btnText, !isPrimary && { color: colors.text }]}>{title}</Text>
      )}
    </Pressable>
  );
}

export function RiskBadge({ level }: { level: RiskLevel }) {
  const c = levelColor(level);
  return (
    <View style={[styles.badge, { backgroundColor: c + '22', borderColor: c }]}>
      <View style={[styles.dot, { backgroundColor: c }]} />
      <Text style={[styles.badgeText, { color: c }]}>{levelLabel(level)}</Text>
    </View>
  );
}

export function TransactionRow({
  tx,
  assessment,
  onPress,
}: {
  tx: Transaction;
  assessment?: Assessment;
  onPress?: () => void;
}) {
  const level = assessment?.level ?? 'ok';
  return (
    <Pressable onPress={onPress} style={styles.row}>
      <View style={{ flex: 1 }}>
        <Text style={styles.rowName}>{tx.payeeName}</Text>
        <Muted style={{ fontSize: 13 }}>
          {new Date(tx.date).toLocaleDateString('de-DE', { day: '2-digit', month: 'short' })} · {tx.category}
        </Muted>
      </View>
      <View style={{ alignItems: 'flex-end', gap: 6 }}>
        <Text style={[styles.rowAmount, tx.amount > 0 ? { color: colors.text } : { color: colors.accent }]}>
          {tx.amount > 0 ? '−' : '+'}
          {Math.abs(tx.amount).toLocaleString('de-DE')} €
        </Text>
        {level !== 'ok' && <RiskBadge level={level} />}
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  title: { color: colors.text, fontSize: 28, fontWeight: '800', letterSpacing: -0.5 },
  subtitle: { color: colors.text, fontSize: 20, fontWeight: '700' },
  body: { color: colors.text, fontSize: 16, lineHeight: 24 },
  muted: { color: colors.muted, fontSize: 15, lineHeight: 22 },
  card: {
    backgroundColor: colors.card,
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: radius,
    padding: 18,
  },
  btn: {
    height: 52,
    borderRadius: 999,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 24,
  },
  btnPrimary: { backgroundColor: colors.brand },
  btnGhost: { backgroundColor: 'transparent', borderWidth: 1, borderColor: colors.border },
  btnText: { color: '#fff', fontSize: 16, fontWeight: '700' },
  badge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    borderWidth: 1,
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 3,
  },
  dot: { width: 7, height: 7, borderRadius: 4 },
  badgeText: { fontSize: 12, fontWeight: '700' },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
    gap: 12,
  },
  rowName: { color: colors.text, fontSize: 16, fontWeight: '600' },
  rowAmount: { fontSize: 16, fontWeight: '700' },
});
