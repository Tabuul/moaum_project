"use client";

/** V396/V398: a BSU- course and its MOAU- twin are one course under two codes. Before a session the central offices see every
 *  department's pairs at once — the ones the duplicates rule suggests, and the ones already linked with how each stands in the
 *  current session — and link them in one act. Each department still sees and links its own on Department courses. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, Panel, PBody, Pil } from "@/components/proto/ui";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";

export interface TwinAcrossSuggestion { dept: string; dept_name: string; bsu_code: string; bsu_title: string; moau_code: string; moau_title: string; level: number; semester: number }
export interface TwinAcrossLinked { id: string; dept: string; dept_name: string; bsu_code: string; bsu_title: string; moau_code: string; level: number; semester: number; linked_at: string; allocation: "NO_CLASSES" | "UNALLOCATED" | "TOGETHER" | "DIFFERENT"; lecturer: string | null }
export interface TwinsAcrossData { session: string | null; suggested: TwinAcrossSuggestion[]; linked: TwinAcrossLinked[] }

const SEM = (n: number) => (n === 1 ? "First" : n === 2 ? "Second" : "Third");
const STAND: Record<TwinAcrossLinked["allocation"], [string, "ok" | "warn" | "grey"]> = {
  TOGETHER: ["Allocated together", "ok"], DIFFERENT: ["Allocated apart", "warn"], UNALLOCATED: ["Not allocated", "grey"], NO_CLASSES: ["No classes yet", "grey"],
};

export function TwinsAcross({ data }: { data: TwinsAcrossData }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [showLinked, setShowLinked] = useState(false);
  const [refused, setRefused] = useState<{ bsuCode: string; moauCode: string; code: string; detail: string }[]>([]);

  async function link(pairs: { bsuCode: string; moauCode: string }[]) {
    setBusy(true);
    setRefused([]);
    try {
      const r = await fetch("/api/bff/api/v1/catalogue/twins/link-all", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Linked ${pairs.length} pair${pairs.length === 1 ? "" : "s"} of courses taught as one`) }, body: JSON.stringify({ pairs }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      const n = Number(j?.linkedNow ?? 0);
      const rf = (j?.refused ?? []) as typeof refused;
      setRefused(rf);
      notify(`${n} pair${n === 1 ? "" : "s"} linked${rf.length ? ` · ${rf.length} refused` : ""}`);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  if (!data.suggested.length && !data.linked.length) return null;
  const byDept = new Map<string, TwinAcrossSuggestion[]>();
  for (const s of data.suggested) byDept.set(s.dept_name, [...(byDept.get(s.dept_name) ?? []), s]);
  return (
    <Panel title="Courses taught as one" right={`${data.linked.length} pair${data.linked.length === 1 ? "" : "s"} linked · ${data.suggested.length} to confirm`}>
      <PBody>
        <div className="sub2 mb-2">
          A <b>BSU-</b> code and its <b>MOAU-</b> twin are one course (300 level and above carry BSU-, 100 and 200 level MOAU-). Linked, the pair is
          allocated, timetabled, registered and examined once; registration, score sheets and results stay per code. Each department can also
          confirm its own on Department courses.
        </div>
        {refused.length ? (
          <div className="notice notice--bad mb-2"><div>
            <div className="notice__t">{refused.length} pair{refused.length === 1 ? " was" : "s were"} not linked</div>
            {refused.map((x) => <p key={`${x.bsuCode}|${x.moauCode}`}><span className="tnum">{x.bsuCode} and {x.moauCode}</span>: {x.detail}</p>)}
          </div></div>
        ) : null}
        {data.suggested.length ? (
          <div className="row row--between mb-2">
            <div className="b600">{data.suggested.length} suggested pair{data.suggested.length === 1 ? "" : "s"} across {byDept.size} department{byDept.size === 1 ? "" : "s"}</div>
            <Btn kind="primary" size="sm" disabled={busy} onClick={() => { if (window.confirm(`Link all ${data.suggested.length} suggested pairs? Each pair's classes in sessions still running are aligned at once.`)) void link(data.suggested.map((s) => ({ bsuCode: s.bsu_code, moauCode: s.moau_code }))); }}>{busy ? "Linking…" : `Link all ${data.suggested.length}`}</Btn>
          </div>
        ) : null}
        {[...byDept.entries()].map(([deptName, rows]) => (
          <div key={deptName} className="mb-2">
            <div className="eyebrow eyebrow--gap">{deptName}</div>
            {rows.map((s) => (
              <div key={`${s.bsu_code}|${s.moau_code}`} className="row row--between" style={{ padding: "6px 0", borderBottom: "1px solid var(--line-2)" }}>
                <div className="grow">
                  <div className="b600 tnum">{s.bsu_code} <span className="sub2">and</span> {s.moau_code}</div>
                  <div className="sub2">{s.bsu_title} · {s.level} Level · {SEM(s.semester)} semester</div>
                </div>
                <Btn kind="secondary" size="sm" disabled={busy} onClick={() => void link([{ bsuCode: s.bsu_code, moauCode: s.moau_code }])}>Link</Btn>
              </div>
            ))}
          </div>
        ))}
        {data.linked.length ? (
          <div className="mt-2">
            <Btn kind="ghost" size="sm" onClick={() => setShowLinked(!showLinked)}>{showLinked ? "Hide" : "Show"} the {data.linked.length} linked pair{data.linked.length === 1 ? "" : "s"}</Btn>
            {showLinked ? data.linked.map((t) => {
              const [word, kind] = STAND[t.allocation];
              return (
                <div key={t.id} className="row row--between" style={{ padding: "6px 0", borderBottom: "1px solid var(--line-2)" }}>
                  <div className="grow">
                    <div className="b600 tnum">{t.bsu_code} <span className="sub2">and</span> {t.moau_code}</div>
                    <div className="sub2">{t.dept_name} · {t.bsu_title} · {t.level} Level · {SEM(t.semester)} semester{t.lecturer ? ` · ${t.lecturer}` : ""}</div>
                  </div>
                  <Pil kind={kind}>{data.session ? `${word} in ${data.session}` : word}</Pil>
                </div>
              );
            }) : null}
          </div>
        ) : null}
      </PBody>
    </Panel>
  );
}
