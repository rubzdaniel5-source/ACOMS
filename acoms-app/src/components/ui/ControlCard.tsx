import Link from "next/link";
import { Icon, type IconName } from "./Icon";

interface StatLine {
  label: string;
  value: number | string;
  tone?: "default" | "amber" | "brick" | "teal";
}

interface Props {
  title: string;
  href: string;
  icon: IconName;
  headline: { value: number | string; label: string };
  stats: StatLine[];
}

const TONE_CLASS: Record<string, string> = {
  default: "text-(--color-text)",
  amber: "text-(--color-warning)",
  brick: "text-(--color-danger)",
  teal: "text-(--color-success)",
};

export function ControlCard({ title, href, icon, headline, stats }: Props) {
  return (
    <Link
      href={href}
      aria-label={`${title}: ${headline.value} ${headline.label}. View details`}
      className="panel flex flex-col p-3 transition-colors hover:border-(--color-primary) hover:bg-(--color-surface-hover) sm:p-5"
    >
      <div className="mb-2 flex items-center gap-2 text-(--color-primary)">
        <Icon name={icon} />
        <h3 className="text-xs font-semibold leading-tight text-(--color-text-muted) sm:text-sm">{title}</h3>
      </div>

      <div className="mb-3">
        <div className="id-code text-2xl font-semibold text-(--color-text) sm:text-3xl">{headline.value}</div>
        <div className="text-xs text-(--color-text-muted) sm:text-sm">{headline.label}</div>
      </div>

      <dl className="space-y-1 border-t border-(--color-border) pt-2 sm:pt-3">
        {stats.map((s) => (
          <div key={s.label} className="flex justify-between gap-2 text-xs sm:text-sm">
            <dt className="text-(--color-text-muted)">{s.label}</dt>
            <dd className={`id-code font-medium ${TONE_CLASS[s.tone ?? "default"]}`}>{s.value}</dd>
          </div>
        ))}
      </dl>

      <div className="mt-auto flex items-center gap-1 pt-3 text-xs font-semibold text-(--color-primary) sm:text-sm">
        View details <Icon name="chevron" size={14} />
      </div>
    </Link>
  );
}
