import { SymbolView, type AndroidSymbol, type SymbolViewProps } from 'expo-symbols';
import type { ColorValue } from 'react-native';
import type { SFSymbol } from 'sf-symbols-typescript';

export type IconName = { ios: SFSymbol; android: AndroidSymbol };

type Props = {
  name: IconName;
  size?: number;
  color: ColorValue;
  weight?: SymbolViewProps['weight'];
};

/** SF Symbols on iOS, Material Symbols on Android. */
export function Icon({ name, size = 22, color, weight }: Props) {
  return (
    <SymbolView
      name={name}
      size={size}
      tintColor={color}
      weight={weight}
      style={{ width: size, height: size }}
    />
  );
}

export const icons = {
  plus: { ios: 'plus', android: 'add' },
  checklist: { ios: 'checklist', android: 'checklist' },
  calendar: { ios: 'calendar', android: 'calendar_month' },
  location: { ios: 'location', android: 'my_location' },
  locationFill: { ios: 'location.fill', android: 'my_location' },
  search: { ios: 'magnifyingglass', android: 'search' },
  close: { ios: 'xmark.circle.fill', android: 'cancel' },
  xmark: { ios: 'xmark', android: 'close' },
  chevronRight: { ios: 'chevron.right', android: 'chevron_right' },
  chevronLeft: { ios: 'chevron.left', android: 'chevron_left' },
  circle: { ios: 'circle', android: 'radio_button_unchecked' },
  checkCircle: { ios: 'checkmark.circle.fill', android: 'check_circle' },
  bell: { ios: 'bell.fill', android: 'notifications' },
  mappin: { ios: 'mappin.circle.fill', android: 'location_on' },
  folder: { ios: 'square.stack.3d.up.fill', android: 'layers' },
  directions: { ios: 'arrow.triangle.turn.up.right.circle.fill', android: 'directions' },
  trash: { ios: 'trash', android: 'delete' },
  check: { ios: 'checkmark', android: 'check' },
} satisfies Record<string, IconName>;
