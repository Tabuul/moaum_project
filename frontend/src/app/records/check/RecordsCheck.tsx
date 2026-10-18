"use client";

/**
 * V536: the Registry's records check — the live students whose record is at odds with itself or the register, by what is wrong,
 * each naming why it matters, the office that corrects it and how. Nothing is changed here: each record is opened and corrected
 * where its office corrects records.
 */
import Link from "next/link";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { useQueryNav } from "@/lib/query-nav";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

export interface IssueKind { code: string; title: string; why: string; corrects: string; offices: string[]; how: string; students: number }
export interface IssueRow {
  student_id: string; matric_no: string | null; admission_no: string | null; name: string; faculty_code: string | null; faculty: string | null;
  programme_code: string | null; programme: string | null; current_level: number | null; entry_mode: string | null; status: string; state: string | null;
  final_level: number | null; issue: string;
  /** V542: what the record most likely should say */
  suggestion?: string | null;
}
export interface RecordsCheckData {
  issue: string | null; faculty: string | null; students: number; total: number; kinds: IssueKind[]; rows: IssueRow[];
  faculties: { code: string; name: string }[];
}

const count = (n: number) => Number(n).toLocaleString("en-NG");
const named = (s: string | null | undefined) =>
  (s ?? "").toLowerCase().replace(/(^|\s)\S/g, (c) => c.toUpperCase()).replace(/ (And|Of|For|In|The) /g, (m) => m.toLowerCase());
const MODE: Record<string, string> = { UTME: "UTME", DIRECT_ENTRY: "Direct entry", TRANSFER: "Transfer", JUPEB: "JUPEB", SANDWICH: "Sandwich", CCE: "CCE", POSTGRADUATE: "Postgraduate" };
const HEAD = ["Issue", "Matric / admission no.", "Name", "Faculty", "Programme", "Level", "Entry mode", "State of origin", "Status", "Corrected by", "Suggestion"];

export function RecordsCheck({ d }: { d: RecordsCheckData }) {
  const nav = useQueryNav();
  const kindOf = new Map(d.kinds.map((k) => [k.code, k]));
  const chosen = d.issue ? kindOf.get(d.issue) ?? null : null;
  const facultyName = d.faculty ? named(d.faculties.find((f) => f.code === d.faculty)?.name ?? d.faculty) : "Every faculty";
  const go = (issue: string | null, faculty: string | null) => {
    const q = new URLSearchParams();
    if (issue) q.set("issue", issue);
    if (faculty) q.set("faculty", faculty);
    nav(`/records/check${q.toString() ? `?${q.toString()}` : ""}`);
  };
  const found = d.kinds.filter((k) => k.students > 0);
  const sub = `${chosen ? chosen.title : "Every issue"} · ${facultyName}`;
  const sheet = () => d.rows.map((r) => [kindOf.get(r.issue)?.title ?? r.issue, r.matric_no ?? r.admission_no ?? "", r.name, named(r.faculty ?? r.faculty_code),
    r.programme ? `${r.programme} (${r.programme_code})` : r.programme_code ?? "", r.current_level ?? "", MODE[r.entry_mode ?? ""] ?? r.entry_mode ?? "",
    r.state ?? "", r.status, kindOf.get(r.issue)?.corrects ?? "", r.suggestion ?? ""]);
  const meta: [string, string][] = [["Issue", chosen ? chosen.title : "Every issue"], ["Faculty", facultyName], ["Records", count(d.total)]];

  return (
    <>
      <Panel title="Student records at odds with the register" right={found.length ? <Pil kind="bad">{count(d.students)} student{d.students === 1 ? "" : "s"}</Pil> : <Pil kind="ok">None</Pil>}>
        <PBody>
          <div className="sub2">
            Every live student (admitted, active or on probation) whose record is inconsistent: a level beyond the programme, the postgraduate entry mode on an undergraduate programme, no state of origin, a programme withdrawn from the register… Each is charged, counted and timetabled wrongly until it is corrected, by the office named beside it. Nothing is changed on this page.
          </div>
          <div className="row row--end mt-2">
            <Field id="rc-fac" label="Faculty">
              <select id="rc-fac" className="ctl" style={{ minWidth: 220 }} value={d.faculty ?? ""} onChange={(e) => go(d.issue, e.target.value || null)}>
                <option value="">Every faculty</option>
                {d.faculties.map((f) => <option key={f.code} value={f.code}>{named(f.name)}</option>)}
              </select>
            </Field>
          </div>
        </PBody>
        <DTable pageSize={0} cols={["What is wrong", "Students|num", "Corrected by", ""]} rows={d.kinds.map((k) => [
          <span key="t"><b>{k.title}</b><div className="sub2">{k.why}</div></span>,
          <b key="n" className="tnum" style={{ color: k.students ? "var(--red-ink)" : undefined }}>{count(k.students)}</b>,
          <span key="c">{k.corrects}</span>,
          k.students ? <Btn key="s" kind={d.issue === k.code ? "primary" : "ghost"} onClick={() => go(d.issue === k.code ? null : k.code, d.faculty)}>{d.issue === k.code ? "Showing" : "Show"}</Btn> : <span key="s" />,
        ])} />
      </Panel>

      {found.length ? (
        <Panel title={chosen ? chosen.title : "Every record to correct"} right={`${count(d.total)} record${d.total === 1 ? "" : "s"}`}>
          <PBody>
            {chosen ? <Note kind="info" title={`Corrected by ${chosen.corrects}`}>{chosen.how}</Note> : null}
            {d.rows.length < d.total ? <div className="sub2">The first {count(d.rows.length)} are listed; choose an issue or a faculty to see the rest.</div> : null}
            <div className="row row--right">
              <Btn kind="ghost" onClick={async () => downloadBlob(await brandedXlsx("Records Check", HEAD, sheet(), { sheetName: "Records check", serial: docSerial("RCK"), sub, meta }), `records-check${d.issue ? `-${d.issue.toLowerCase()}` : ""}.xlsx`)}>Download Excel</Btn>
              <Btn kind="ghost" onClick={() => brandedPrint("Records Check", sub, HEAD, sheet(), docSerial("RCK"), { meta, orientation: "landscape" })}>Download PDF</Btn>
            </div>
          </PBody>
          <DTable pageSize={25}
            cols={[...(chosen ? [] : ["What is wrong"]), "Student", "Programme", "Level", "Entry mode", "State of origin", "Status"]}
            texts={d.rows.map((r) => `${r.matric_no ?? ""} ${r.admission_no ?? ""} ${r.name} ${r.programme ?? ""} ${r.programme_code ?? ""} ${r.faculty ?? ""} ${r.state ?? ""}`)}
            rows={d.rows.map((r) => [
              ...(chosen ? [] : [<span key="i">{kindOf.get(r.issue)?.title ?? r.issue}</span>]),
              <span key="s"><Link href={`/students/${r.student_id}`}><b>{r.name}</b></Link><div className="sub2 tnum">{r.matric_no ?? r.admission_no ?? "No number yet"}</div></span>,
              <span key="p">{r.programme ?? <span className="sub2">{r.programme_code ?? "None"}</span>}<div className="sub2">{named(r.faculty ?? r.faculty_code)}{r.final_level ? ` · final level ${r.final_level}` : ""}</div>{r.suggestion ? <div className="sub2"><b>Suggested:</b> {r.suggestion}</div> : null}</span>,
              <span key="l" className="tnum">{r.current_level ?? "—"}</span>,
              <span key="m">{MODE[r.entry_mode ?? ""] ?? r.entry_mode ?? "—"}</span>,
              <span key="o">{r.state ?? <span className="sub2">None</span>}</span>,
              <span key="st">{named(r.status)}</span>,
            ])} />
        </Panel>
      ) : (
        <Note kind="ok" title="Every live student's record is consistent">No level beyond a programme, no undergraduate with the postgraduate entry mode, every state of origin given and spelt as the register spells it.</Note>
      )}
    </>
  );
}
