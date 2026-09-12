import Link from "next/link";

interface StatLine {
  label: string;
  value: number | string;
  tone?: "default" | "amber" | "brick" | "teal";
}

interface Props {
  title: string;
  href: string;
  headline: { value: number | string; label: string };
  stats: StatLine[];
}

const TONE_CLASS: Record<string, string> = {
  default: "text-(--foreground)",
  amber: "text-(--amber)",
  brick: "text-(--brick)",
  teal: "text-(--teal)",
};

export function ControlCard({ title, href, headline, stats }: Props) {
  return (
    <Link href={href} className="panel block p-5 hover:border-(--navy) transition-colors">
      <h3 className="mb-3 text-xs font-semibold uppercase tracking-wide text-(--steel)">{title}</h3>

      <div className="mb-4">
        <div className="id-code text-3xl font-semibold text-(--navy)">{headline.value}</div>
        <div className="text-sm text-(--steel)">{headline.label}</div>
      </div>

      <div className="space-y-1 border-t pt-3" style={{ borderColor: "var(--border)" }}>
        {stats.map((s) => (
          <div key={s.label} className="flex justify-between text-sm">
            <span className="text-(--steel)">{s.label}</span>
            <span className={`id-code font-medium ${TONE_CLASS[s.tone ?? "default"]}`}>{s.value}</span>
          </div>
        ))}
      </div>

      <div className="mt-4 text-xs font-semibold text-(--navy)">VIEW DETAILS →</div>
    </Link>
  );
}
