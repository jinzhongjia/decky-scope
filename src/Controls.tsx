import type { ReactNode } from "react";
import { DialogButton, Focusable } from "@decky/ui";
export function Segments<T extends string | number>({
  value,
  options,
  onChange,
  className = "ds-nav",
  label,
  disabled = false,
}: {
  value: T;
  options: { value: T; label: string }[];
  onChange: (value: T) => void;
  className?: string;
  label: string;
  disabled?: boolean;
}) {
  return (
    <Focusable
      className={className}
      flow-children="horizontal"
      aria-label={label}
    >
      {options.map((option) => (
        <DialogButton
          key={option.value}
          disabled={disabled}
          aria-pressed={value === option.value}
          onClick={() => onChange(option.value)}
        >
          {option.label}
        </DialogButton>
      ))}
    </Focusable>
  );
}
export function Row({
  label,
  value,
  long = false,
}: {
  label: string;
  value: ReactNode;
  long?: boolean;
}) {
  return (
    <Focusable
      {...{ focusable: true }}
      className={`ds-kv${long ? " ds-kv-long" : ""}`}
    >
      <dt>{label}</dt>
      <dd>
        {value === null || value === undefined || value === "" ? "—" : value}
      </dd>
    </Focusable>
  );
}
export function Section({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <section className="ds-section">
      <h3>{title}</h3>
      {children}
    </section>
  );
}
