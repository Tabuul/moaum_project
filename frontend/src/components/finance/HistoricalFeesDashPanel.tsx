"use client";

/**
 * V654: the Bursar's and the Students Account Officer's dashboards — historical financial clearance: graduates owing, cleared, to
 * review, awaiting the Bursar, the amounts; each figure opens its graduates on Historical Fees & Clearance. Read after the page
 * is drawn, so the dashboard never waits on it.
 */
import { useEffect, useState } from "react";
import { LinkBtn, Panel, PBody, Tiles } from "@/components/proto/ui";
import { naira, num, type Figures } from "@/lib/historical-fees";

const LINK = "/finance/historical";

export function HistoricalFeesDashPanel({ officer = false }: { officer?: boolean }) {
  const [f, setF] = useState<Figures | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let live = true;
    fetch(`/api/bff/api/v1/finance/historical/figures`, { cache: "no-store", headers: { "X-Background": "1" } })
      .then(async (r) => { const j = r.ok ? ((await r.json()) as Figures) : null; if (live) { setF(j); setFailed(!j); } })
      .catch(() => { if (live) setFailed(true); });
    return () => { live = false; };
  }, []);
  if (failed) return null;
  const pending = f?.assessments.find((x) => x.state === "PENDING_BURSAR_APPROVAL")?.n ?? 0;
  const returned = f?.assessments.find((x) => x.state === "RETURNED_FOR_CORRECTION")?.n ?? 0;
  const v = (n: number | undefined) => (f ? Number(n ?? 0).toLocaleString("en-GB") : "…");
  return (
    <Panel title={officer ? "Historical fee review" : "Historical financial clearance"} right={<LinkBtn kind="ghost" href={LINK}>Historical Fees &amp; Clearance</LinkBtn>}>
      <PBody>
        <Tiles items={officer ? [
          ["Requires historical review", v(f?.requires_review), f?.requires_review ? "var(--red-ink)" : null, "Graduates with a semester no amount is known for", `${LINK}?financial=HISTORICAL_FEE_REVIEW_REQUIRED`],
          ["Returned to you", v(returned), returned ? "var(--amber-ink)" : null, "Assessments the Bursar sent back", `${LINK}?tab=approvals`],
          ["Pending Bursar approval", v(pending), null, "Submitted, awaiting the Bursar", `${LINK}?tab=approvals`],
          ["Students with outstanding fees", v(f?.with_outstanding), f?.with_outstanding ? "var(--red-ink)" : null, f ? naira(f.outstanding) : "…", `${LINK}?filter=OUTSTANDING`],
        ] : [
          ["Ready to graduate", v(f?.readyToGraduate?.ready), f?.readyToGraduate?.ready ? "var(--green-ink)" : null, `${v(f?.readyToGraduate?.waiting)} waiting on the Bursary's confirmation`, "/clearance/ready"],
          ["Total graduated students", v(f?.graduates), null, "Graduates and approved graduands", `${LINK}?tab=students`],
          ["Students with outstanding fees", v(f?.with_outstanding), f?.with_outstanding ? "var(--red-ink)" : null, f ? naira(f.outstanding) : "…", `${LINK}?filter=OUTSTANDING`],
          ["Students fully cleared", v(f?.cleared), "var(--green-ink)", "Nothing owed, nothing to assess", `${LINK}?financial=FINANCIALLY_CLEARED`],
          ["Pending historical assessment", v(f?.requires_review), f?.requires_review ? "var(--amber-ink)" : null, "A semester with no fee structure", `${LINK}?financial=HISTORICAL_FEE_REVIEW_REQUIRED`],
          ["Pending Bursar approval", v(pending), pending ? "var(--amber-ink)" : null, `${v(f?.pending_approval)} graduates waiting on it`, `${LINK}?tab=approvals`],
          ["Total historical amount assessed", f ? naira(f.assessed) : "…", null, `${f ? naira(f.paid) : "…"} paid`, `${LINK}?tab=reports`],
          ["Total historical outstanding", f ? naira(f.outstanding) : "…", f && num(f.outstanding) > 0 ? "var(--red-ink)" : null, "On what is assessed", `${LINK}?financial=FINANCIAL_OBLIGATION`],
        ]} />
      </PBody>
    </Panel>
  );
}
