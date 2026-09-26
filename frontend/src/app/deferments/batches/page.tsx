import Link from "next/link";
import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { SEM, dayOf, type Batch } from "@/lib/deferments";

export const dynamic = "force-dynamic";

/** the batches the Academic Office has forwarded to the DVC: number, count, session, date, officer, and where each stands */
export default async function BatchesPage() {
  const [me, r] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Batch[]>("/api/v1/deferments/batches")]);
  const rows = r.ok ? r.data : [];
  return (
    <Shell route="t/deferments" me={me.ok ? me.data : null}>
      <PageHead title="Forwarding Batches" description="Every list of faculty-approved deferment applications the Academic Office forwarded to the Deputy Vice-Chancellor, numbered DEF-DVC-YYYY-NNNNN, with the applications it named and the DVC's progress on them." actions={<LinkBtn href="/deferments">Deferments Desk</LinkBtn>} />
      {!r.ok ? <ProblemNotice problem={r.problem} /> : null}
      <Panel title="Batches" right={`${rows.length}`}>
        {rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Batch", "Session · semester", "Applications|num", "Forwarded|mid", "By", "Awaiting DVC|num", "Approved|num", "Rejected|num", "Returned|num", "DVC status|mid", "|num"]}
            rows={rows.map((b, i) => [
              <span key="sn" className="tnum sub2">{i + 1}</span>,
              <span key="r" className="tnum b600">{b.reference}</span>,
              <span key="s" className="tnum">{b.session ?? "Mixed"}{b.semester ? ` · ${SEM(b.semester)}` : ""}</span>,
              <span key="n" className="tnum">{b.count}</span>,
              <span key="d" className="tnum sub2">{dayOf(b.forwarded_at)}</span>,
              <span key="o" className="sub2">{b.forwarded_officer ?? b.office ?? ""}{b.note ? <div>{b.note}</div> : null}</span>,
              <span key="a" className="tnum">{b.awaiting_dvc}</span>, <span key="ap" className="tnum">{b.approved}</span>, <span key="rj" className="tnum">{b.rejected}</span>, <span key="rt" className="tnum">{b.returned}</span>,
              <Pil key="st" kind={b.dvc_status === "OPEN" ? "warn" : "ok"}>{b.dvc_status === "OPEN" ? "With the DVC" : "Decided"}</Pil>,
              <Link key="v" className="btn btn--ghost btn--sm" href={`/deferments?batch=${encodeURIComponent(b.reference)}`}>Applications</Link>,
            ])} texts={rows.map((b) => `${b.reference} ${b.session ?? ""} ${b.forwarded_officer ?? ""}`)} />
        ) : <PBody><Note kind="info" title="No batch has been forwarded">The Academic Office forwards faculty-approved applications to the DVC from the deferments desk; each forwarding is a batch here.</Note></PBody>}
      </Panel>
    </Shell>
  );
}
