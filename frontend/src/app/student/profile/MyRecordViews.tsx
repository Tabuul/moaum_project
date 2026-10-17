import { Panel, PBody } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { officeLabel } from "@/lib/offices";

export interface MyRecordView { at: string; office: string; office_label: string | null; record: "STUDENT_RECORD" | "SUPPORT_RECORD" }

const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" });

/** V530: which office opened the student's record, and when — the last twelve months (the officer's name is Internal Audit's to read) */
export function MyRecordViews({ rows }: { rows: MyRecordView[] }) {
  return (
    <Panel title="Who has opened your record" right={<span className="sub2">The last twelve months</span>}>
      <PBody>
        <div className="sub2">
          Each time a University office opened your student record, or ICT Support its record of you, it is noted here: once for each
          office within ten minutes. The name of the officer is kept for Internal Audit, who can be asked about any of these.
        </div>
      </PBody>
      {rows.length ? (
        <DTable pageSize={10} cols={["When|mid", "Office", "Record"]} rows={rows.map((r, i) => [
          <span className="tnum sub2" key={"w" + i}>{when(r.at)}</span>,
          <span key={"o" + i}>{r.office_label ?? officeLabel(r.office)}</span>,
          <span key={"r" + i} className="sub2">{r.record === "SUPPORT_RECORD" ? "ICT Support's record" : "Student record"}</span>,
        ])} texts={rows.map((r) => `${r.office_label ?? r.office}`)} />
      ) : <PBody><div className="sub2">No office has opened your record in the last twelve months.</div></PBody>}
    </Panel>
  );
}
