import { stateKind, stateWord } from "@/lib/clearance";
import { Note, Panel, PBody, Pil } from "@/components/proto/ui";

export interface SupportClearanceData {
  processes: {
    id: string; reference: string; workflow_label: string; session: string; completed_at: string | null; cancelled_at: string | null; overall: string;
    stages: { unit: string; label: string; required: boolean; applies: boolean; opened: boolean; state: string; item: string | null; decided_at: string | null; officer: string | null }[];
    documents: { unit: string; label: string; state: string; superseded: boolean }[];
  }[];
}
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "");

/** the student's clearance as an ICT Support agent may see it (V415): which office is pending, what it asked, the documents'
 *  states — never an office's internal note or evidence, and nothing to act on: the offices decide, the desk explains */
export function SupportClearance({ data }: { data: SupportClearanceData }) {
  if (!data.processes.length) return <Note kind="info" title="No clearance has been started for this student" />;
  return (
    <>
      {data.processes.map((p) => (
        <Panel key={p.id} title={`${p.workflow_label} · ${p.session}`} right={<span className="row row--tight"><span className="sub2 tnum">{p.reference}</span><Pil kind={stateKind(p.cancelled_at ? "CANCELLED" : p.overall)}>{stateWord(p.cancelled_at ? "CANCELLED" : p.overall)}</Pil></span>}>
          <PBody>
            {p.stages.map((s) => (
              <div key={s.unit} className="row row--tight" style={{ padding: "4px 0", borderBottom: "1px solid var(--line-2)" }}>
                <b style={{ minWidth: 120 }}>{s.label}</b>
                <Pil kind={stateKind(s.state)}>{stateWord(s.state)}</Pil>
                <span className="sub2 grow">{[s.item, s.officer ? `${s.officer}, ${when(s.decided_at)}` : null].filter(Boolean).join(" · ")}</span>
              </div>
            ))}
            {p.documents.filter((d) => !d.superseded).length ? (
              <div className="sub2 mt-1">Documents: {p.documents.filter((d) => !d.superseded).map((d) => `${d.label} (${d.state.replace(/_/g, " ").toLowerCase()})`).join(" · ")}</div>
            ) : null}
          </PBody>
        </Panel>
      ))}
      <div className="sub2">Each office decides its own stage; refer the student to the office pending, or raise a ticket for a technical fault.</div>
    </>
  );
}
