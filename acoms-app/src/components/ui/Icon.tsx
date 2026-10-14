// One line-icon family (24px grid, 1.75 stroke, round caps), inline so no new
// dependency is needed. Icons are decorative; labels carry the meaning.
const PATHS: Record<string, React.ReactNode> = {
  boxes: <><path d="M3 8l9-5 9 5-9 5-9-5z" /><path d="M3 8v8l9 5 9-5V8" /><path d="M12 13v8" /></>,
  gauge: <><path d="M4 18a9 9 0 1116 0" /><path d="M12 18l4-6" /></>,
  swap: <><path d="M7 4L3 8l4 4" /><path d="M3 8h14" /><path d="M17 20l4-4-4-4" /><path d="M21 16H7" /></>,
  alert: <><path d="M12 3l10 18H2L12 3z" /><path d="M12 10v5" /><path d="M12 18.5v.01" /></>,
  check: <><circle cx="12" cy="12" r="9" /><path d="M8 12l3 3 5-6" /></>,
  building: <><path d="M4 21V5l8-2 8 2v16" /><path d="M9 21v-5h6v5" /><path d="M8 9h.01M12 9h.01M16 9h.01M8 13h.01M12 13h.01M16 13h.01" /></>,
  chevron: <path d="M9 6l6 6-6 6" />,
};

export type IconName = keyof typeof PATHS;

export function Icon({ name, size = 20 }: { name: IconName; size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {PATHS[name]}
    </svg>
  );
}
