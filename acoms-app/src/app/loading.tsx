import { TableSkeleton } from "@/components/ui/Skeleton";

// Shown while any page without its own loading screen is fetching data.
export default function Loading() {
  return <TableSkeleton label="Loading page" />;
}
