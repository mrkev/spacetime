export type TimedItem = {
  key: string;
  /** Minutes from midnight. */
  startMinute: number;
  endMinute: number;
};

export type PositionedItem<T> = T & { column: number; columns: number };

/** Short items still take up this much room, so they don't visually collide. */
const MIN_VISUAL_MINUTES = 20;

/**
 * Lays out overlapping items side by side, the way Calendar does: items that overlap form a
 * cluster, each item takes the first free column, and every item in a cluster shares its width.
 */
export function layoutDay<T extends TimedItem>(items: T[]): PositionedItem<T>[] {
  const sorted = [...items].sort(
    (a, b) => a.startMinute - b.startMinute || b.endMinute - a.endMinute,
  );
  const result: PositionedItem<T>[] = [];
  let cluster: PositionedItem<T>[] = [];
  let columnEnds: number[] = [];
  let clusterEnd = -Infinity;

  const flush = () => {
    for (const item of cluster) item.columns = columnEnds.length;
    result.push(...cluster);
    cluster = [];
    columnEnds = [];
  };

  for (const item of sorted) {
    const visualEnd = Math.max(item.endMinute, item.startMinute + MIN_VISUAL_MINUTES);
    if (item.startMinute >= clusterEnd) flush();

    let column = columnEnds.findIndex((end) => end <= item.startMinute);
    if (column === -1) {
      column = columnEnds.length;
      columnEnds.push(visualEnd);
    } else {
      columnEnds[column] = visualEnd;
    }
    cluster.push({ ...item, column, columns: 1 });
    clusterEnd = Math.max(clusterEnd, visualEnd);
  }
  flush();
  return result;
}
