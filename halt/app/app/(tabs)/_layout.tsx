import { Tabs } from 'expo-router';
import { Text } from 'react-native';
import { colors } from '../../src/theme';
import { useStore } from '../../src/store/useStore';

function Icon({ label, focused }: { label: string; focused: boolean }) {
  return <Text style={{ fontSize: 20, opacity: focused ? 1 : 0.5 }}>{label}</Text>;
}

export default function TabsLayout() {
  const openAlerts = useStore((s) => s.alerts.filter((a) => !a.resolution).length);
  return (
    <Tabs
      screenOptions={{
        headerStyle: { backgroundColor: colors.bg },
        headerTintColor: colors.text,
        headerTitleStyle: { fontWeight: '800' },
        headerShadowVisible: false,
        tabBarStyle: { backgroundColor: colors.bgSoft, borderTopColor: colors.border },
        tabBarActiveTintColor: colors.brand,
        tabBarInactiveTintColor: colors.muted,
      }}
    >
      <Tabs.Screen
        name="index"
        options={{ title: 'Aktivität', tabBarIcon: ({ focused }) => <Icon label="📈" focused={focused} /> }}
      />
      <Tabs.Screen
        name="alerts"
        options={{
          title: 'Warnungen',
          tabBarBadge: openAlerts > 0 ? openAlerts : undefined,
          tabBarIcon: ({ focused }) => <Icon label="🔔" focused={focused} />,
        }}
      />
      <Tabs.Screen
        name="settings"
        options={{ title: 'Einstellungen', tabBarIcon: ({ focused }) => <Icon label="⚙️" focused={focused} /> }}
      />
    </Tabs>
  );
}
