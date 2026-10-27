import { distanceMeters, formatDistance } from '../geo';
import { withAlpha } from '../theme';

describe('distanceMeters', () => {
  it('is zero for the same point', () => {
    const p = { latitude: 37.7749, longitude: -122.4194 };
    expect(distanceMeters(p, p)).toBe(0);
  });

  it('matches a known distance', () => {
    // Ferry Building to Coit Tower is roughly 1.2 km.
    const ferry = { latitude: 37.7955, longitude: -122.3937 };
    const coit = { latitude: 37.8024, longitude: -122.4058 };
    expect(distanceMeters(ferry, coit)).toBeGreaterThan(1200);
    expect(distanceMeters(ferry, coit)).toBeLessThan(1400);
  });
});

describe('formatDistance', () => {
  it('uses meters below a kilometer', () => {
    expect(formatDistance(250.4)).toBe('250 m');
    expect(formatDistance(1500)).toBe('1.5 km');
    expect(formatDistance(12_345)).toBe('12 km');
  });
});

describe('withAlpha', () => {
  it('appends an alpha channel', () => {
    expect(withAlpha('#FF3B30', 0.5)).toBe('#FF3B3080');
    expect(withAlpha('#abc', 1)).toBe('#aabbccff');
    expect(withAlpha('red', 0.5)).toBe('red');
  });
});
