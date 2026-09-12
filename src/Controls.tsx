import type { ReactNode } from "react";
import {
  DialogButton,
  Field,
  Focusable,
  PanelSection,
  PanelSectionRow,
} from "@decky/ui";

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

// A flex row alone does not describe the gamepad navigation tree.
export function Actions({ children }: { children: ReactNode }) {
  return (
    <Focusable className="ds-actions" flow-children="horizontal">
      {children}
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
    <PanelSectionRow>
      <Field
        label={label}
        focusable
        padding="standard"
        bottomSeparator="standard"
        childrenLayout={long ? "below" : "inline"}
        className="ds-kv"
      >
        <span className="ds-field-value">
          {value === null || value === undefined || value === "" ? "—" : value}
        </span>
      </Field>
    </PanelSectionRow>
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
    <div className="ds-section">
      <PanelSection title={title}>{children}</PanelSection>
    </div>
  );
}
