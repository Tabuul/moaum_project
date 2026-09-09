/**
 * Pure formatters, safe to call from either a server component or a client one.
 *
 * These once lived in components/proto/blocks.tsx, which is "use client"; a
 * plain function exported from a client module cannot be *called* from a server
 * component (only rendered as a component or passed as a prop), so a server
 * dashboard that called money()/day() threw at render. They live here, with no
 * "use client", and blocks.tsx re-exports them so existing client imports keep
 * working unchanged.
 */

/** the money helper: ₦ and thousands */
export function money(n: number): string {
  return "₦" + n.toLocaleString("en-NG");
}

/** a date as the prototype prints one: "12 Oct 2026" */
export function day(iso: string | null | undefined, withYear = true): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: withYear ? "numeric" : undefined });
}
