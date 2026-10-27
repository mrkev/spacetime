import { layoutDay } from '../layout';

const item = (key: string, start: number, end: number) => ({
  key,
  startMinute: start,
  endMinute: end,
});

const byKey = <T extends { key: string }>(items: T[]) =>
  Object.fromEntries(items.map((i) => [i.key, i]));

describe('layoutDay', () => {
  it('gives non-overlapping items the full width', () => {
    const result = byKey(layoutDay([item('a', 540, 600), item('b', 600, 660)]));
    expect(result.a).toMatchObject({ column: 0, columns: 1 });
    expect(result.b).toMatchObject({ column: 0, columns: 1 });
  });

  it('places overlapping items side by side', () => {
    const result = byKey(layoutDay([item('a', 540, 660), item('b', 570, 630)]));
    expect(result.a).toMatchObject({ column: 0, columns: 2 });
    expect(result.b).toMatchObject({ column: 1, columns: 2 });
  });

  it('reuses a freed column within the same cluster', () => {
    // a spans the whole cluster; b ends before c starts, so c can take b's column.
    const result = byKey(
      layoutDay([item('a', 540, 720), item('b', 540, 600), item('c', 610, 700)]),
    );
    expect(result.a.columns).toBe(2);
    expect(result.b.column).toBe(1);
    expect(result.c.column).toBe(1);
  });

  it('keeps separate clusters independent', () => {
    const result = byKey(
      layoutDay([item('a', 540, 600), item('b', 550, 600), item('c', 800, 860)]),
    );
    expect(result.a.columns).toBe(2);
    expect(result.c).toMatchObject({ column: 0, columns: 1 });
  });

  it('treats very short items as if they had a minimum height', () => {
    // A 5-minute item would visually overlap one starting 10 minutes later.
    const result = byKey(layoutDay([item('a', 540, 545), item('b', 550, 600)]));
    expect(result.a.columns).toBe(2);
  });

  it('puts longer items first when they start together', () => {
    const result = byKey(layoutDay([item('short', 540, 570), item('long', 540, 660)]));
    expect(result.long.column).toBe(0);
    expect(result.short.column).toBe(1);
  });

  it('gives short items room for their drawn height when zoomed out', () => {
    // Five-minute items ten minutes apart only collide once their minimum height covers the gap.
    const items = [item('a', 540, 545), item('b', 550, 555)];
    expect(byKey(layoutDay(items, 5)).b).toMatchObject({ column: 0, columns: 1 });
    expect(byKey(layoutDay(items, 30)).b).toMatchObject({ column: 1, columns: 2 });
  });
});
