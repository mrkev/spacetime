import { useSegments } from 'expo-router';
import { NativeTabs } from 'expo-router/native-tabs';

import { runNowAction, type TabName } from '../../lib/nowAction';
import { useTheme } from '../../lib/theme';
import { openTimeTab } from '../../time/timeLevel';

export default function TabLayout() {
  const theme = useTheme();
  const segments = useSegments();
  const tab: TabName = segments[1] === 'time' ? 'time' : 'space';

  return (
    <NativeTabs tintColor={theme.tint}>
      <NativeTabs.Trigger name="space">
        <NativeTabs.Trigger.Label>Space</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf={{ default: 'map', selected: 'map.fill' }} md="map" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="time" listeners={{ tabPress: openTimeTab }}>
        <NativeTabs.Trigger.Label>Time</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="calendar" md="calendar_month" />
      </NativeTabs.Trigger>
      {/* The search role puts this in the floating slot at the trailing end of the tab bar. It's
          disabled so it never opens its (empty) tab; the press runs the current tab's action. */}
      <NativeTabs.Trigger
        name="now"
        role="search"
        disabled
        accessibilityLabel={tab === 'time' ? 'Today' : 'Here'}
        listeners={{ tabPress: () => runNowAction(tab) }}
      >
        <NativeTabs.Trigger.Label>{tab === 'time' ? 'Today' : 'Here'}</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon
          sf={tab === 'time' ? 'calendar.badge.clock' : 'location.fill'}
          md={tab === 'time' ? 'today' : 'my_location'}
        />
      </NativeTabs.Trigger>
    </NativeTabs>
  );
}
