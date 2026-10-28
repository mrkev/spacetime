import { useColorScheme } from 'react-native';

// iOS system colors, so the app feels at home next to Calendar and Maps.
const light = {
  tint: '#FF3B30',
  blue: '#007AFF',
  background: '#FFFFFF',
  groupedBackground: '#F2F2F7',
  card: '#FFFFFF',
  fill: '#E5E5EA',
  text: '#000000',
  secondaryText: '#8E8E93',
  tertiaryText: '#C7C7CC',
  separator: '#C6C6C8',
  hourLine: '#E5E5EA',
  overlay: '#FFFFFF',
  shadow: '#000000',
};

const dark: typeof light = {
  tint: '#FF453A',
  blue: '#0A84FF',
  background: '#000000',
  groupedBackground: '#000000',
  card: '#1C1C1E',
  fill: '#2C2C2E',
  text: '#FFFFFF',
  secondaryText: '#8E8E93',
  tertiaryText: '#48484A',
  separator: '#38383A',
  hourLine: '#2C2C2E',
  overlay: '#1C1C1E',
  shadow: '#000000',
};

export type Theme = typeof light;

export function useTheme(): Theme {
  return useColorScheme() === 'dark' ? dark : light;
}

export const PIN_COLORS = [
  '#FF3B30', // red
  '#FF9500', // orange
  '#FFCC00', // yellow
  '#34C759', // green
  '#00C7BE', // mint
  '#30B0C7', // teal
  '#007AFF', // blue
  '#5856D6', // indigo
  '#AF52DE', // purple
  '#FF2D55', // pink
  '#A2845E', // brown
  '#8E8E93', // gray
];

/**
 * Puts a marker balloon's tip on its coordinate. MapKit offsets MKMarkerAnnotationView by this
 * much itself, but react-native-maps overwrites it with the `centerOffset` prop, which defaults
 * to zero and centers the balloon on the coordinate instead.
 */
export const PIN_OFFSET = { x: 0, y: -14 };

/** Appends an alpha channel to a #RRGGBB color. */
export function withAlpha(hex: string, alpha: number): string {
  const normalized = normalizeHex(hex);
  if (!normalized) return hex;
  const a = Math.round(Math.max(0, Math.min(1, alpha)) * 255)
    .toString(16)
    .padStart(2, '0');
  return `${normalized}${a}`;
}

function normalizeHex(color: string): string | null {
  const match = /^#?([0-9a-f]{3}|[0-9a-f]{6})([0-9a-f]{2})?$/i.exec(color.trim());
  if (!match) return null;
  let rgb = match[1];
  if (rgb.length === 3)
    rgb = rgb
      .split('')
      .map((c) => c + c)
      .join('');
  return `#${rgb}`;
}
