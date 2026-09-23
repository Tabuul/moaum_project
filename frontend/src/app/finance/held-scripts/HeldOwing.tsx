import Link from "next/link";
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface HeldOwingRow {
  student_id: string; number: string; surname: string; other_names: string; programme_name: string; level: number; session: string;
  scripts: number; courses: string; closes_on: string | null; due: number | null; paid: number | null; balance: number | null;
}

const money = (n: number | null) => (n == null ? "—" : `₦${Number(n).toLocaleString("en-NG", { minimumFractionDigits: 0, maximumFractionDigits: 0 })}`);
/** the closing date is within a fortnight */
const closingSoon = (iso: string | null) => !!iso && new Date(iso).getTime() - Date.now() < 14 * 86400000;
const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "no date set");

/** the students a lecturer's held script is waiting on: each pays, registers, and the mark is released */
export function HeldOwing({ rows }: { rows: HeldOwingRow[] }) {
  const scripts = rows.reduce((a, r) => a + Number(r.scripts), 0);
  const owing = rows.filter((r) => Number(r.balance ?? 0) > 0);
  const balance = owing.reduce((a, r) => a + Number(r.balance ?? 0), 0);
  const soon = rows.filter((r) => closingSoon(r.closes_on)).length;
  return (
    <>
      <Tiles items={[
        ["Students", String(rows.length), rows.length ? "var(--red-ink)" : "var(--green-ink)", "A script held, waiting on registration"],
        ["Scripts held", String(scripts), null, "Marks not yet on any sheet"],
        ["Still owing", money(balance), balance ? "var(--red-ink)" : null, `${owing.length} student${owing.length === 1 ? "" : "s"} with a balance`],
        ["Closing within 14 days", String(soon), soon ? "var(--red-ink)" : null, "Late registration closes; the script lapses"],
      ]} />
      <Note kind="info" title="What this list is">
        Each of these students sat a paper they had not registered for, usually because fees were owing at registration. The lecturer held the script. The mark is released into the score sheet the moment the student pays, registers the course and the Head of Department approves the registration — nothing else is needed. After the semester&rsquo;s late-registration date the held script lapses and the result is lost. This is the most persuasive fees reminder the University can send.
      </Note>
      <Panel title="Students a held script is waiting on" right={`${rows.length} student${rows.length === 1 ? "" : "s"}`}>
        {rows.length ? (
          <DTable cols={["Matriculation number", "Name", "Programme", "Session|mid", "Courses held", "Closes|mid", "Due|num", "Paid|num", "Balance|num"]} rows={rows.map((r) => [
            <span className="tnum" key="n">{r.number}</span>,
            <span key="nm"><strong>{r.surname}, {r.other_names}</strong><div className="sub2">{r.level} level</div></span>,
            <span className="sub2" key="p">{r.programme_name}</span>,
            <span className="tnum" key="s">{r.session}</span>,
            <span key="c"><Pil kind="info">{r.scripts} script{Number(r.scripts) === 1 ? "" : "s"}</Pil><div className="sub2 tnum">{r.courses}</div></span>,
            <span className="sub2" key="d" style={closingSoon(r.closes_on) ? { color: "var(--red-ink)", fontWeight: 600 } : undefined}>{day(r.closes_on)}</span>,
            <span className="tnum" key="due">{money(r.due)}</span>,
            <span className="tnum" key="paid">{money(r.paid)}</span>,
            <span className="tnum" key="bal" style={Number(r.balance ?? 0) > 0 ? { color: "var(--red-ink)", fontWeight: 700 } : { color: "var(--green-ink)" }}>{money(r.balance)}</span>,
          ])} texts={rows.map((r) => `${r.number} ${r.surname} ${r.other_names} ${r.programme_name} ${r.courses}`)} />
        ) : <PBody><div className="sub2">No script is held anywhere. When a lecturer holds one, the student appears here with what they owe. <Link href="/finance/fees">Fee setup</Link>.</div></PBody>}
      </Panel>
    </>
  );
}
