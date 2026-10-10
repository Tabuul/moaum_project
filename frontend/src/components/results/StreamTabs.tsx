"use client";

/** V381: the full-time students' results or the Centre for Continuing Education's — one stream at a time, never the two mixed.
 *  The choice lives in the address (?stream=CCE), so the server reads the stream it was asked for. */
import { usePathname, useSearchParams } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { Tabs } from "@/components/proto/ui";
import type { Stream } from "@/lib/results";

export function StreamTabs({ stream }: { stream: Stream }) {
  const queryNav = useQueryNav();
  const pathname = usePathname();
  const params = useSearchParams();
  return (
    <Tabs<Stream> label="Students" value={stream}
      items={[{ id: "REGULAR", label: "Full-time" }, { id: "CCE", label: "CCE (part-time)" }]}
      onChange={(next) => {
        const q = new URLSearchParams(params.toString());
        if (next === "CCE") q.set("stream", "CCE");
        else q.delete("stream");
        queryNav(`${pathname}?${q.toString()}`);
      }} />
  );
}
