import { File, Paths } from 'expo-file-system';
import { SymbolView, type SFSymbol } from 'expo-symbols';
import { Image, View } from 'react-native';

import type { Theme } from '../lib/theme';
import { pinColor, type MapPlace } from './places';
import type { Collection } from './store';

/**
 * A place's icon: `symbol:<SF Symbol name>` for one picked for it, or `image:<path>` for a point of
 * interest's own icon from Apple Maps, saved under the app's Documents directory. Map markers take
 * the same strings as their `glyph`.
 */
export type PlaceIconName = string;

/** Icons to pick from, by group. */
export const ICON_GROUPS: { title: string; symbols: SFSymbol[] }[] = [
  {
    title: 'Food & Drink',
    symbols: [
      'fork.knife',
      'cup.and.saucer.fill',
      'mug.fill',
      'wineglass.fill',
      'birthday.cake.fill',
      'takeoutbag.and.cup.and.straw.fill',
      'carrot.fill',
      'fish.fill',
      'popcorn.fill',
      'frying.pan.fill',
    ],
  },
  {
    title: 'Shopping',
    symbols: [
      'cart.fill',
      'bag.fill',
      'basket.fill',
      'storefront.fill',
      'tshirt.fill',
      'book.fill',
      'gift.fill',
    ],
  },
  {
    title: 'Health & Fitness',
    symbols: [
      'dumbbell.fill',
      'figure.run',
      'figure.yoga',
      'figure.pool.swim',
      'sportscourt.fill',
      'cross.case.fill',
      'pills.fill',
      'stethoscope',
    ],
  },
  {
    title: 'Home & Work',
    symbols: [
      'house.fill',
      'building.2.fill',
      'briefcase.fill',
      'laptopcomputer',
      'graduationcap.fill',
      'person.2.fill',
      'pawprint.fill',
      'wrench.and.screwdriver.fill',
      'scissors',
    ],
  },
  {
    title: 'Getting Around',
    symbols: [
      'airplane',
      'tram.fill',
      'bus.fill',
      'car.fill',
      'fuelpump.fill',
      'bicycle',
      'parkingsign',
      'bed.double.fill',
    ],
  },
  {
    title: 'Outdoors',
    symbols: [
      'tree.fill',
      'leaf.fill',
      'mountain.2.fill',
      'figure.hiking',
      'tent.fill',
      'beach.umbrella.fill',
      'sun.max.fill',
    ],
  },
  {
    title: 'Culture & Fun',
    symbols: [
      'theatermasks.fill',
      'film.fill',
      'music.note',
      'paintpalette.fill',
      'building.columns.fill',
      'ticket.fill',
      'gamecontroller.fill',
    ],
  },
  {
    title: 'Other',
    symbols: ['star.fill', 'heart.fill', 'flag.fill', 'bookmark.fill', 'sparkles', 'mappin'],
  },
];

/** Its pin's color, or blue for a place that's only been found (with nothing at it yet). */
export function badgeColor(place: MapPlace, collections: Collection[], theme: Theme): string {
  const found = !place.saved && place.todos.length === 0 && place.events.length === 0;
  return found ? theme.blue : pinColor(place, collections, theme.tint);
}

export function symbolIcon(symbol: SFSymbol): PlaceIconName {
  return `symbol:${symbol}`;
}

/** The icon itself, tinted `color`. Without one, a pin. */
export function PlaceGlyph({
  icon,
  size,
  color,
}: {
  icon?: PlaceIconName;
  size: number;
  color: string;
}) {
  if (icon?.startsWith('image:')) {
    const { uri } = new File(Paths.document, icon.slice('image:'.length));
    return (
      <Image
        source={{ uri }}
        style={{ width: size, height: size, tintColor: color }}
        resizeMode="contain"
      />
    );
  }
  const symbol = (
    icon?.startsWith('symbol:') ? icon.slice('symbol:'.length) : 'mappin'
  ) as SFSymbol;
  return (
    <SymbolView
      name={symbol}
      size={size}
      tintColor={color}
      resizeMode="scaleAspectFit"
      style={{ width: size, height: size }}
    />
  );
}

/** The icon in a circle of the place's color, like its pin. */
export function PlaceBadge({
  icon,
  color,
  size = 32,
}: {
  icon?: PlaceIconName;
  color: string;
  size?: number;
}) {
  return (
    <View
      style={{
        width: size,
        height: size,
        borderRadius: size / 2,
        backgroundColor: color,
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      <PlaceGlyph icon={icon} size={size * 0.55} color="#fff" />
    </View>
  );
}
