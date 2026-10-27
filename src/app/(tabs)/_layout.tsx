import { NativeTabs } from 'expo-router/native-tabs';

import { useTheme } from '../../lib/theme';

export default function TabLayout() {
  const theme = useTheme();
  return (
    <NativeTabs tintColor={theme.tint}>
      <NativeTabs.Trigger name="space">
        <NativeTabs.Trigger.Label>Space</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf={{ default: 'map', selected: 'map.fill' }} md="map" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="time">
        <NativeTabs.Trigger.Label>Time</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="calendar" md="calendar_month" />
      </NativeTabs.Trigger>
    </NativeTabs>
  );
}
