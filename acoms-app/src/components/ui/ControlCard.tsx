import Link from "next/link";
import { Icon, type IconName } from "./Icon";

interface StatLine {
  label: string;
  value: number | string;
  tone?: "default" | "amber" | "brick" | "teal";
  /** Filtered list this count opens. Omit when no list matches the count. */
  href?: string;
}

interface Props {
  title: string;
  href: string;
  icon: IconName;
  headline: { value: number | string; label: string; href?: string };
  stats: StatLine[];
}

const TONE_CLASS: Record<string, string> = {
  default: "text-(--color-text)",
  amber: "text-(--color-warning)",
  brick: "text-(--color-danger)",
  teal: "text-(--color-success)",
};

// The card is a container, not one big link, so each count can be its own link
// (nested anchors are invalid). The title/headline and "View details" open the
// card's main view; each sub-KPI with an href opens its filtered list.
export function ControlCard({ title, href, icon, headline, stats }: Props) {
  return (
    <div className="panel flex flex-col p-3 sm:p-5">
      <Link
        href={headline.href ?? href}
        aria-label={`${title}: ${headline.value} ${headline.label}`}
        className="mb-3 block rounded-md hover:bg-(--color-surface-hover)"
      >
        <span className="mb-2 flex items-center gap-2 text-(--color-primary)">
          <Icon name={icon} />
          <span className="text-xs font-semibold leading-tight text-(--color-text-muted) sm:text-sm">{title}</span>
        </span>
        <span className="id-code block text-2xl font-semibold text-(--color-text) sm:text-3xl">{headline.value}</span>
        <span className="block text-xs text-(--color-text-muted) sm:text-sm">{headline.label}</span>
      </Link>

      <ul className="space-y-0.5 border-t border-(--color-border) pt-2 sm:pt-3">
        {stats.map((s) => {
          const inner = (
            <>
              <span className="text-(--color-text-muted)">{s.label}</span>
              <span className={`id-code font-medium ${TONE_CLASS[s.tone ?? "default"]}`}>{s.value}</span>
            </>
          );
          return (
            <li key={s.label}>
              {s.href ? (
                <Link
                  href={s.href}
                  aria-label={`${s.label}: ${s.value}. Open list`}
                  className="flex min-h-7 items-center justify-between gap-2 rounded px-1 -mx-1 text-xs hover:bg-(--color-surface-hover) hover:underline sm:text-sm"
                >
                  {inner}
                </Link>
              ) : (
                <div className="flex min-h-7 items-center justify-between gap-2 text-xs sm:text-sm">{inner}</div>
              )}
            </li>
          );
        })}
      </ul>

      <Link
        href={href}
        className="mt-auto inline-flex items-center gap-1 pt-3 text-xs font-semibold text-(--color-primary) hover:underline sm:text-sm"
      >
        View details <Icon name="chevron" size={14} />
      </Link>
    </div>
  );
}
