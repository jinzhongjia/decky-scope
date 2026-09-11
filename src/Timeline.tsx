import { useEffect, useRef } from "react";
import { History } from "./api";
import { formatMetric, t } from "./i18n";
export function Timeline({ data }: { data: History | null }) {
  const base = useRef<HTMLCanvasElement>(null);
  const wrapper = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const draw = () => {
      const canvas = base.current;
      if (!canvas) return;
      const width = Math.max(240, canvas.clientWidth),
        height = 220,
        dpr = window.devicePixelRatio || 1;
      canvas.width = width * dpr;
      canvas.height = height * dpr;
      const ctx = canvas.getContext("2d");
      if (!ctx) return;
      ctx.scale(dpr, dpr);
      ctx.clearRect(0, 0, width, height);
      const valid =
        data?.samples.filter(
          (p) => p.value !== null && Number.isFinite(p.value),
        ) || [];
      ctx.font = "14px sans-serif";
      ctx.fillStyle = "#a9bbca";
      if (!valid.length || !data) {
        ctx.fillText(t("noData"), 24, 110);
        return;
      }
      const lo = Math.min(...valid.map((p) => p.min ?? p.value!));
      const hi = Math.max(lo + 1, ...valid.map((p) => p.max ?? p.value!));
      const start = data.samples[0].ts_wall_ms,
        end = Math.max(
          start + 1,
          data.samples[data.samples.length - 1].ts_wall_ms,
        );
      const x = (time: number) =>
        65 + ((time - start) / (end - start)) * (width - 85);
      const y = (value: number) => 176 - ((value - lo) / (hi - lo)) * 140;
      ctx.strokeStyle = "#29414f";
      for (let i = 0; i < 4; i++) {
        const row = 36 + (i * 140) / 3;
        ctx.beginPath();
        ctx.moveTo(65, row);
        ctx.lineTo(width - 20, row);
        ctx.stroke();
      }
      ctx.fillText(formatMetric(data.metric, hi), 0, 30);
      ctx.fillText(formatMetric(data.metric, lo), 0, 180);
      ctx.fillText(new Date(start).toLocaleTimeString(), 65, 211);
      ctx.fillText(
        new Date(end).toLocaleTimeString(),
        Math.max(150, width - 105),
        211,
      );
      ctx.strokeStyle = "#66d6c3";
      ctx.lineWidth = 2;
      ctx.beginPath();
      let drawing = false;
      let previousTime = 0;
      for (const point of data.samples) {
        if (point.value === null) {
          drawing = false;
          continue;
        }
        if (
          previousTime &&
          point.ts_wall_ms - previousTime >
            Math.max(
              data.resolution_ms * 3,
              ((end - start) / Math.max(data.samples.length, 1)) * 3,
            )
        )
          drawing = false;
        if (drawing) ctx.lineTo(x(point.ts_wall_ms), y(point.value));
        else ctx.moveTo(x(point.ts_wall_ms), y(point.value));
        drawing = true;
        previousTime = point.ts_wall_ms;
      }
      ctx.stroke();
      if (valid.length === 1) {
        ctx.beginPath();
        ctx.arc(x(valid[0].ts_wall_ms), y(valid[0].value!), 3, 0, Math.PI * 2);
        ctx.fillStyle = "#66d6c3";
        ctx.fill();
      }
    };
    draw();
    const resize = new ResizeObserver(draw);
    if (wrapper.current) resize.observe(wrapper.current);
    return () => resize.disconnect();
  }, [data]);
  return (
    <div
      ref={wrapper}
      style={{ position: "relative", height: 220, width: "100%" }}
    >
      <canvas
        ref={base}
        aria-label={data?.metric || t("history")}
        style={{ width: "100%", height: 220 }}
      />
    </div>
  );
}
