"use client";

/** V577: when the GST/EPS figures and lists were worked out (the population is kept, worked out again behind the screens once five
 *  minutes old, and at once after the GST fee or its setting changes), with Refresh to work them out now. The refresh asked for is
 *  taken out of the address once the page has it, so a reload does not ask again. */
import { useEffect } from "react";
import { usePathname, useSearchParams } from "next/navigation";
import Link from "next/link";

export function KeptAt({ at }: { at?: string | null }) {
  const path = usePathname();
  const params = useSearchParams();
  useEffect(() => {
    if (params.get("refresh") === "1" && typeof window !== "undefined") {
      const q = new URLSearchParams(params.toString());
      q.delete("refresh");
      window.history.replaceState(null, "", `${path}${q.toString() ? `?${q.toString()}` : ""}`);
    }
  }, [params, path]);
  if (!at) return null;
  const q = new URLSearchParams(params.toString());
  q.set("refresh", "1");
  const when = new Date(at).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
  return (
    <span className="sub2">
      Figures as of {when} · <Link href={`${path}?${q.toString()}`} prefetch={false}>Refresh</Link>
    </span>
  );
}
