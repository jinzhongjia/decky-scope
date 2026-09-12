import type { History, Sample } from "./api";
export type Point = History["samples"][number];
export const LIVE_LIMIT = 360;
export function appendRecent(points: Sample[], sample: Sample): Sample[] {
  const last = points[points.length - 1];
  if (last && sample.ts_wall_ms < last.ts_wall_ms) return [sample];
  const next =
    last?.ts_wall_ms === sample.ts_wall_ms ? points.slice(0, -1) : points;
  return [...next.slice(-(LIVE_LIMIT - 1)), sample];
}
export function validateHistory(data: History, metric: string): History {
  if (
    !data ||
    data.metric !== metric ||
    !Number.isFinite(data.resolution_ms) ||
    data.resolution_ms <= 0 ||
    !Array.isArray(data.samples) ||
    data.samples.length > 1200 ||
    data.samples.some(
      (p) =>
        !p ||
        !Number.isFinite(p.ts_wall_ms) ||
        (p.value !== null && !Number.isFinite(p.value)),
    )
  )
    throw Error("invalid_history");
  const finite = (v: unknown) =>
    typeof v === "number" && Number.isFinite(v) && v >= 0;
  const c = data.coverage;
  if (
    c &&
    (!finite(c.from_ms) ||
      !finite(c.to_ms) ||
      c.from_ms > c.to_ms ||
      !finite(c.estimated_covered_ms) ||
      !finite(c.uncovered_ms) ||
      c.estimated_covered_ms > c.to_ms - c.from_ms ||
      !Array.isArray(c.gaps) ||
      c.gaps.length > 256 ||
      c.gaps.some(
        (g) => !finite(g.from_ms) || !finite(g.to_ms) || g.from_ms > g.to_ms,
      ))
  )
    throw Error("invalid_coverage");
  if (
    data.events &&
    (!Array.isArray(data.events) ||
      data.events.length > 128 ||
      data.events.some(
        (e) =>
          !["suspend_resume", "clock_change"].includes(e.kind) ||
          !finite(e.from_ms) ||
          !finite(e.to_ms),
      ))
  )
    throw Error("invalid_events");
  return data;
}
export function mergeTrend(
  history: History | null,
  recent: Sample[],
  metric: string,
  from: number,
  to: number,
): Point[] {
  const map = new Map<number, Point>();
  for (const p of history?.samples || [])
    if (p.ts_wall_ms >= from && p.ts_wall_ms <= to) map.set(p.ts_wall_ms, p);
  const edge = Math.max(-Infinity, ...map.keys());
  for (const sample of recent) {
    if (
      sample.ts_wall_ms < from ||
      sample.ts_wall_ms > to ||
      sample.ts_wall_ms <= edge
    )
      continue;
    map.set(sample.ts_wall_ms, {
      ts_wall_ms: sample.ts_wall_ms,
      value: Number.isFinite(sample[metric]) ? sample[metric] : null,
    });
  }
  return [...map.values()]
    .sort((a, b) => a.ts_wall_ms - b.ts_wall_ms)
    .slice(-600);
}
export function chartDomain(points: Point[], metric: string): [number, number] {
  if (metric === "cpu_pct_x10") return [0, 1000];
  if (metric === "gpu_pct") return [0, 100];
  if (metric.startsWith("psi_")) return [0, 10000];
  const values = points
    .map((p) => p.value)
    .filter((v): v is number => v !== null && Number.isFinite(v));
  const low = Math.min(0, ...values),
    high = Math.max(1000, ...values);
  const step = Math.max(1000, Math.pow(10, Math.floor(Math.log10(high - low))));
  return [Math.floor(low / step) * step, Math.ceil(high / step) * step];
}
export function splitSegments(
  points: Point[],
  gapMs: number,
  gaps: { from_ms: number; to_ms: number }[] = [],
): Point[][] {
  const segments: Point[][] = [];
  let segment: Point[] = [];
  for (const p of points) {
    if (
      p.value === null ||
      (segment.length &&
        (p.ts_wall_ms - segment[segment.length - 1].ts_wall_ms > gapMs ||
          gaps.some(
            (g) =>
              segment[segment.length - 1].ts_wall_ms < g.to_ms &&
              p.ts_wall_ms > g.from_ms,
          )))
    ) {
      if (segment.length) segments.push(segment);
      segment = [];
    }
    if (p.value !== null) segment.push(p);
  }
  if (segment.length) segments.push(segment);
  return segments;
}
