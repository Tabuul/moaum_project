"use client";

/** V396: a BSU- course and its MOAU- twin — one course under two codes (300 level and above carry BSU-, 100 and 200 level
 *  MOAU-) — linked so the class is allocated, timetabled and registered once. Registration, score sheets and results stay per
 *  code. Suggested from the duplicates rule; linked and unlinked by the department or a central office. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, Panel, PBody, Pil } from "@/components/proto/ui";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";

export interface TwinPair {
  id: string; bsu_code: string; bsu_title: string; moau_code: string; moau_title: string; level: number; semester: number;
  linked_at: string; linked_by: string | null; allocation: "NO_CLASSES" | "UNALLOCATED" | "TOGETHER" | "DIFFERENT"; lecturer: string | null;
}
export interface TwinSuggestion { bsu_code: string; bsu_title: string; moau_code: string; moau_title: string; level: number; semester: number }
export interface Twins { dept: string; session: string | null; linked: TwinPair[]; suggested: TwinSuggestion[] }

const SEM = (n: number) => (n === 1 ? "First" : n === 2 ? "Second" : "Third");
const STAND: Record<TwinPair["allocation"], [string, "ok" | "warn" | "grey"]> = {
  TOGETHER: ["Allocated together", "ok"],
  DIFFERENT: ["Allocated apart", "warn"],
  UNALLOCATED: ["Not allocated", "grey"],
  NO_CLASSES: ["No classes yet", "grey"],
};

export function TwinCourses({ twins, mayLink }: { twins: Twins; mayLink: boolean }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);

  async function send(path: string, body: unknown, reason: string) {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(reason);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  if (!twins.linked.length) return null; // V402: pairs are no longer suggested; only a pair linked earlier is shown, to be unlinked
  return (
    <Panel title="Pairs still linked" right={`${twins.linked.length} linked`}>
      <PBody>
        <div className="sub2 mb-2">
          A <b>BSU-</b> code and its <b>MOAU-</b> twin are not linked as a rule: both stay offered, and each cohort registers its own code (the rule is
          stated on All courses). A pair linked earlier is still allocated, timetabled and registered as one until it is unlinked here.
        </div>
        {twins.linked.map((t) => {
          const [word, kind] = STAND[t.allocation];
          return (
            <div key={t.id} className="row row--between" style={{ padding: "8px 0", borderBottom: "1px solid var(--line-2)" }}>
              <div className="grow">
                <div className="b600 tnum">{t.bsu_code} <span className="sub2">and</span> {t.moau_code}</div>
                <div className="sub2">{t.bsu_title} · {t.level} Level · {SEM(t.semester)} semester{t.lecturer ? ` · ${t.lecturer}` : ""}</div>
              </div>
              <Pil kind={kind}>{twins.session ? `${word} in ${twins.session}` : word}</Pil>
              {mayLink ? (
                <Btn kind="ghost" size="sm" disabled={busy} onClick={() => {
                  const why = window.prompt(`Unlink ${t.bsu_code} and ${t.moau_code}? Each keeps its classes as they are and is taught on its own from then. Say why:`);
                  if (why && why.trim()) void send(`/twins/${t.id}/unlink`, { reason: why.trim() }, `Unlinked ${t.bsu_code} and ${t.moau_code}`);
                }}>Unlink</Btn>
              ) : null}
            </div>
          );
        })}
      </PBody>
    </Panel>
  );
}
