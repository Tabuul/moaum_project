"use client";
/** V675: old-portal PG applicants migrated, counted on the School's dashboards (admissions.pg_legacy_figures): each count opens the
 *  records behind it on the migration desk. Read after the page is drawn, so the dashboard never waits on it. */
import { useEffect, useState } from "react";
import { LinkBtn, Panel, PBody, Tiles } from "@/components/proto/ui";

interface Figures {
  legacyApplicants: number; migrated: number; pending: number; offered: number; accepted: number; screened: number; students: number;
  duplicates: number; conflicts: number; review: number; documentsMissing: number; unmappedProgrammes: number; feesUnderReview: number;
}

const DESK = "/admissions/postgraduate/migration";

export function PgLegacyPanel() {
  const [f, setF] = useState<Figures | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/pg/migration/figures", { cache: "no-store", headers: { "X-Background": "1" } })
      .then(async (r) => { const j = r.ok ? ((await r.json()) as Figures) : null; if (live) { setF(j); setFailed(!j); } })
      .catch(() => { if (live) setFailed(true); });
    return () => { live = false; };
  }, []);
  const n = (v: number | undefined) => (f ? Number(v ?? 0).toLocaleString() : "…");
  const warn = (v: number | undefined) => (f && v ? "var(--amber-ink)" : null);
  return (
    <Panel title="Legacy PG migration" right={<LinkBtn href={DESK}>Migration desk</LinkBtn>}>
      {failed ? <PBody><div className="sub2">The migration&rsquo;s counts could not be read just now.</div></PBody> : (
        <PBody>
          <Tiles items={[
            ["Total legacy applicants", n(f?.legacyApplicants), null, "Migrated, linked or in an upload", `${DESK}?view=migrated`],
            ["Migrated applicants", n(f?.migrated), null, "Old number kept beside the new", `${DESK}?view=migrated`],
            ["Pending migration", n(f?.pending), warn(f?.pending), "Checked, not yet imported", `${DESK}?view=pending`],
            ["Admitted applicants", n(f?.offered), null, "Offer stands, not yet accepted", `${DESK}?view=offered`],
            ["Accepted applicants", n(f?.accepted), null, "Offer accepted", `${DESK}?view=accepted`],
            ["Screened applicants", n(f?.screened), null, "Cleared on the old portal", `${DESK}?view=screened`],
            ["Active PG students", n(f?.students), null, "Migrated and on the register", `${DESK}?view=students`],
            ["Duplicate applicants", n(f?.duplicates), warn(f?.duplicates), "Repeated in an upload", `${DESK}?view=duplicates`],
            ["Conflicts", n(f?.conflicts), warn(f?.conflicts), "Identity or decision differs", `${DESK}?view=conflicts`],
            ["Requires review", n(f?.review), warn(f?.review), "Not matched with confidence", `${DESK}?view=review`],
            ["Missing documents", n(f?.documentsMissing), warn(f?.documentsMissing), "Old reference, file not attached", `${DESK}?view=documents`],
            ["Unmapped programmes", n(f?.unmappedProgrammes), warn(f?.unmappedProgrammes), "Old programmes to map", `${DESK}?view=review`],
          ]} />
        </PBody>
      )}
    </Panel>
  );
}
