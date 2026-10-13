"use client";

/**
 * V424, on the Result pipeline, for the Registry and the result desks: the results held for the Senate's decision (withheld,
 * incomplete, malpractice) in scope — how long each has waited, against the days after which the Registry is reminded, and
 * the amendment carrying the decision when one is open — and the students owing a course only because of a recorded absence
 * (V422's rule), before registration. Both read only, loaded after the page; an office that may not read them sees nothing.
 */
import { useEffect, useState } from "react";
import type { Scope } from "@/lib/scope";
import { STAGE_LABEL } from "@/lib/results";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { Btn, LinkBtn, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

interface Held {
  student_id: string; number: string; name: string; programme_code: string; course_code: string; title: string; dept_name: string;
  session: string; semester: number; outcome: string; sheet_id: string; held_since: string; days: number; amendment_ref: string | null; amendment_stage: string | null;
}
interface Owed { student_id: string; number: string; name: string; programme: string; level: number | null; status: string; course_code: string; title: string; units: number; absent_in: string }

const OUTCOME: Record<string, string> = { WITHHELD: "Withheld", INCOMPLETE: "Incomplete", MALPRACTICE: "Malpractice case" };
const sem = (n: number) => (n === 1 ? "first" : n === 2 ? "second" : `semester ${n}`);

function useScoped<T>(path: string, scope: Scope): T | null | "denied" {
  const [v, setV] = useState<T | null | "denied">(null);
  useEffect(() => {
    let live = true;
    const q = new URLSearchParams();
    for (const [k, val] of Object.entries({ fac: scope.fac, dept: scope.dept, prog: scope.prog })) if (val) q.set(k, val);
    void fetch(`/api/bff/api/v1/results/${path}?${q}`, { cache: "no-store" }).then(async (r) => {
      if (live) setV(r.ok ? ((await r.json()) as T) : "denied");
    }).catch(() => { if (live) setV("denied"); });
    return () => { live = false; };
  }, [path, scope.fac, scope.dept, scope.prog]);
  return v;
}

export function HeldForSenate({ scope }: { scope: Scope }) {
  const v = useScoped<{ remindDays: number; rows: Held[] }>("held", scope);
  if (v === "denied") return null;
  const rows = v?.rows ?? [];
  const late = v ? rows.filter((r) => v.remindDays > 0 && r.days >= v.remindDays).length : 0;
  async function download() {
    const head = ["S/N", "Matriculation number", "Name", "Programme", "Course", "Title", "Department", "Session", "Semester", "Held as", "Held since", "Days", "Amendment"];
    const body = rows.map((r, i) => [i + 1, r.number, r.name, r.programme_code, r.course_code, r.title, r.dept_name, r.session, r.semester, OUTCOME[r.outcome] ?? r.outcome,
      r.held_since.slice(0, 10), r.days, r.amendment_ref ? `${r.amendment_ref} (${STAGE_LABEL[r.amendment_stage ?? ""]?.[0] ?? r.amendment_stage})` : ""]);
    downloadBlob(await brandedXlsx("Results Held for the Senate", head, body, { sheetName: "Held", serial: docSerial("RHS") }), "results-held-for-the-senate.xlsx");
  }
  return (
    <Panel title={`Held for the Senate · ${v ? rows.length : "…"}`} right={rows.length ? <Btn kind="ghost" onClick={() => void download()}>Download</Btn> : v ? "None held" : "Reading…"}>
      <PBody>
        <p className="sub2">
          Withheld, incomplete and malpractice results wait for the Senate&rsquo;s decision: never counted, never owed, and the student&rsquo;s semester stays open.
          The decision is recorded as an amendment of the mark, raised by the course&rsquo;s lecturer or the Programme Examinations Officer.
          {v && v.remindDays > 0 ? ` The Registry is reminded of any held longer than ${v.remindDays} days.` : v ? " No reminder is set." : ""}
        </p>
        {rows.length ? (
          <DTable cols={["Student", "Course", "Held as|mid", "Session", "Waiting|num", "Decision", "|num"]} rows={rows.map((r) => [
            <span key="s">{r.name}<span className="sub2 tnum" style={{ display: "block" }}>{r.number} · {r.programme_code}</span></span>,
            <span key="c"><b className="tnum">{r.course_code}</b><span className="sub2" style={{ display: "block" }}>{r.dept_name}</span></span>,
            <Pil key="o" kind="warn">{OUTCOME[r.outcome] ?? r.outcome}</Pil>,
            <span key="p" className="tnum sub2">{`${r.session}, ${sem(r.semester)}`}</span>,
            <span key="d" className={`tnum${v && v.remindDays > 0 && r.days >= v.remindDays ? " ink-red b600" : ""}`}>{`${r.days} day${r.days === 1 ? "" : "s"}`}</span>,
            r.amendment_ref ? <span key="a"><span className="tnum">{r.amendment_ref}</span><span className="sub2" style={{ display: "block" }}>{`At ${STAGE_LABEL[r.amendment_stage ?? ""]?.[0] ?? r.amendment_stage}`}</span></span>
              : <span key="a" className="sub2">No amendment yet</span>,
            <LinkBtn key="x" kind="ghost" href={`/results/chain?sheet=${r.sheet_id}`}>Open</LinkBtn>,
          ])} texts={rows.map((r) => `${r.number} ${r.name} ${r.course_code} ${r.title} ${r.outcome} ${r.session}`)} />
        ) : null}
        {late ? <p className="sub2 ink-red">{`${late} held longer than ${v?.remindDays ?? ""} days.`}</p> : null}
      </PBody>
    </Panel>
  );
}

export function OwedAfterAbsence({ scope }: { scope: Scope }) {
  const v = useScoped<Owed[]>("absence-carryovers", scope);
  if (v === "denied") return null;
  const rows = v ?? [];
  async function download() {
    const head = ["S/N", "Matriculation number", "Name", "Programme", "Level", "Status", "Course", "Title", "Units", "Absent in"];
    const body = rows.map((r, i) => [i + 1, r.number, r.name, r.programme, r.level ?? "", r.status, r.course_code, r.title, r.units, r.absent_in]);
    downloadBlob(await brandedXlsx("Owed After a Recorded Absence", head, body, { sheetName: "Owed", serial: docSerial("ROA") }), "owed-after-a-recorded-absence.xlsx");
  }
  return (
    <Panel title={`Owed after a recorded absence · ${v ? rows.length : "…"}`} right={rows.length ? <Btn kind="ghost" onClick={() => void download()}>Download</Btn> : v ? "Nobody" : "Reading…"}>
      <PBody>
        <p className="sub2">
          A recorded absence is an F and the course is owed (V422). These students owe a course only because of an absence, so it now
          comes back at registration as a carryover. A course also owed for a graded F was owed before and is not listed.
        </p>
        {rows.length ? (
          <DTable cols={["Student", "Programme", "Level|num", "Course", "Absent in"]} rows={rows.map((r) => [
            <span key="s">{r.name}<span className="sub2 tnum" style={{ display: "block" }}>{r.number}</span></span>,
            <span key="p" className="sub2">{r.programme}</span>,
            <span key="l" className="tnum">{r.level ?? "—"}</span>,
            <span key="c"><b className="tnum">{r.course_code}</b><span className="sub2" style={{ display: "block" }}>{r.title}</span></span>,
            <span key="a" className="tnum sub2">{r.absent_in}</span>,
          ])} texts={rows.map((r) => `${r.number} ${r.name} ${r.programme} ${r.course_code} ${r.title}`)} />
        ) : null}
      </PBody>
    </Panel>
  );
}
