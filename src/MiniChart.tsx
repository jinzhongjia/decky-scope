import { useEffect, useRef } from "react";
import { chartDomain, Point, splitSegments } from "./trends";
import { formatMetric, t } from "./i18n";
export function MiniChart({
  points,
  metric,
  color,
  from,
  to,
  gapMs,
  compact = false,
}: {
  points: Point[];
  metric: string;
  color: string;
  from: number;
  to: number;
  gapMs: number;
  compact?: boolean;
}) {
  const ref = useRef<HTMLCanvasElement>(null);
  const domain = chartDomain(points, metric);
  const hasData = points.some((p) => p.value !== null);
  useEffect(() => {
    const draw = () => {
      const canvas = ref.current;
      if (!canvas) return;
      const width = canvas.clientWidth,
        height = compact ? 40 : 50;
      if (width <= 0) return;
      const dpr = canvas.ownerDocument.defaultView?.devicePixelRatio || 1;
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      const c = canvas.getContext("2d");
      if (!c) return;
      c.scale(dpr, dpr);
      const [lo, hi] = chartDomain(points, metric);
      const x = (time: number) =>
        2 + ((time - from) / Math.max(1, to - from)) * (width - 4);
      const y = (value: number) =>
        height - 4 - ((value - lo) / (hi - lo)) * (height - 8);
      c.strokeStyle = "rgba(160,187,211,.12)";
      c.lineWidth = 1;
      for (const ratio of [0, 0.5, 1]) {
        const yy = 4 + (height - 8) * ratio;
        c.beginPath();
        c.moveTo(0, yy);
        c.lineTo(width, yy);
        c.stroke();
      }
      const gradient = c.createLinearGradient(0, 0, 0, height);
      gradient.addColorStop(0, color + "32");
      gradient.addColorStop(1, color + "00");
      for (const segment of splitSegments(points, gapMs)) {
        if (segment.length > 1) {
          c.beginPath();
          c.moveTo(x(segment[0].ts_wall_ms), y(0));
          for (const p of segment) c.lineTo(x(p.ts_wall_ms), y(p.value!));
          c.lineTo(x(segment[segment.length - 1].ts_wall_ms), y(0));
          c.closePath();
          c.fillStyle = gradient;
          c.fill();
        }
        c.beginPath();
        segment.forEach((p, i) =>
          i
            ? c.lineTo(x(p.ts_wall_ms), y(p.value!))
            : c.moveTo(x(p.ts_wall_ms), y(p.value!)),
        );
        c.strokeStyle = color;
        c.lineWidth = 1.5;
        c.stroke();
        const last = segment[segment.length - 1];
        c.beginPath();
        c.arc(x(last.ts_wall_ms), y(last.value!), 1.8, 0, Math.PI * 2);
        c.fillStyle = color;
        c.fill();
      }
    };
    draw();
    const observer = new ResizeObserver(draw);
    if (ref.current) observer.observe(ref.current);
    return () => observer.disconnect();
  }, [points, metric, color, from, to, gapMs, compact]);
  return (
    <div className="ds-chart" style={{ height: compact ? 40 : 50 }}>
      <canvas
        ref={ref}
        role="img"
        aria-label={`${metric}: ${formatMetric(metric, domain[0])} – ${formatMetric(metric, domain[1])}`}
        style={{ width: "100%", height: compact ? 40 : 50 }}
      />
      <span className="ds-chart-scale">{formatMetric(metric, domain[1])}</span>
      {domain[0] < 0 && (
        <span className="ds-chart-floor">
          {formatMetric(metric, domain[0])}
        </span>
      )}
      {!hasData && <span className="ds-chart-empty">{t("noReadings")}</span>}
    </div>
  );
}
