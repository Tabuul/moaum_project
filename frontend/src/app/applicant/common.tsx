"use client";

/**
 * What every applicant screen shares (proto/part13.html): the rail of ten
 * stages, the two-column grid, and one way of posting an act to the API and
 * refreshing the screen from what the database now says.
 */
import { useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { STAGES, type Application } from "@/lib/applicant";
import { Panel } from "@/components/proto/ui";
import { Step } from "@/components/proto/blocks";

/* stage N means milestone N is complete, so N is ticked and N+1 is in hand */
export function Rail({ a }: { a: Application }) {
  return (
    <Panel title="Your application" right={STAGES[Math.min(a.stage, 9)][0]}>
      <div style={{ padding: "4px 0" }}>
        {STAGES.map((s, i) => (
          <div key={s[0]} style={{ padding: "9px 16px", borderTop: i ? "1px solid var(--line-2)" : undefined }}>
            <Step state={a.stage >= i ? "done" : a.stage + 1 === i ? "now" : "todo"} title={s[0]} sub={s[1]} />
          </div>
        ))}
      </div>
    </Panel>
  );
}

export function TwoCol({ children }: { children: ReactNode }) {
  return <div className="grid grid--2" style={{ alignItems: "start" }}>{children}</div>;
}

export function StepList({ list }: { list: ["done" | "now" | "todo", ReactNode, ReactNode][] }) {
  return (
    <div style={{ padding: "4px 0" }}>
      {list.map((x, i) => (
        <div key={i} style={{ padding: "9px 16px", borderTop: i ? "1px solid var(--line-2)" : undefined }}>
          <Step state={x[0]} title={x[1]} sub={x[2]} />
        </div>
      ))}
    </div>
  );
}

/** one act against the applicant's own application; the screen re-reads what the database now says */
export function useAct() {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  async function act(key: string, method: "POST" | "PUT", path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(key);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/applicant${path}`, {
        method,
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) },
        body: JSON.stringify(body ?? {}),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText });
        return null;
      }
      router.refresh();
      return (j ?? {}) as Record<string, unknown>;
    } finally {
      setBusy(null);
    }
  }
  return { act, busy, problem, setProblem };
}

export function when(iso: string | null | undefined): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit" });
}

export function onDay(iso: string | null | undefined): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
}

export function clock(t: string | null | undefined): string {
  return t ? String(t).slice(0, 5) : "—";
}
