// Stable loading placeholders. Pulse is disabled for reduced-motion users in globals.css.
export function SkeletonBlock({ className = "" }: { className?: string }) {
  return <div aria-hidden="true" className={`animate-pulse rounded-md bg-(--color-surface-subtle) ${className}`} />;
}

export function CardGridSkeleton() {
  return (
    <div role="status" aria-label="Loading dashboard" className="mx-auto w-full max-w-7xl px-3 py-6 sm:px-6">
      <SkeletonBlock className="mb-2 h-8 w-64" />
      <SkeletonBlock className="mb-6 h-4 w-80 max-w-full" />
      <div className="grid grid-cols-1 gap-3 min-[360px]:grid-cols-2 sm:gap-4 lg:grid-cols-3">
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} className="panel p-3 sm:p-5">
            <SkeletonBlock className="mb-3 h-4 w-32" />
            <SkeletonBlock className="mb-2 h-8 w-16" />
            <SkeletonBlock className="mb-4 h-3 w-28" />
            <SkeletonBlock className="mb-2 h-3 w-full" />
            <SkeletonBlock className="h-3 w-full" />
          </div>
        ))}
      </div>
      <span className="sr-only">Loading figures</span>
    </div>
  );
}

export function TableSkeleton({ label = "Loading" }: { label?: string }) {
  return (
    <div role="status" aria-label={label} className="mx-auto w-full max-w-7xl px-3 py-6 sm:px-6">
      <SkeletonBlock className="mb-2 h-8 w-56" />
      <SkeletonBlock className="mb-6 h-4 w-72 max-w-full" />
      <div className="panel p-4">
        {Array.from({ length: 8 }).map((_, i) => (
          <SkeletonBlock key={i} className="mb-3 h-6 w-full last:mb-0" />
        ))}
      </div>
      <span className="sr-only">{label}</span>
    </div>
  );
}
