"use client";

/**
 * V651: the PG School's dashboards — the students of each stage in the School's session (700, 700 Extension; 800 A–C; 900 A–E),
 * fresh and returning, those past the maximum period or awaiting a restart; each count opens its students. Read after the page is
 * drawn, so the dashboard never waits on it.
 */
import { useEffect, useState } from "react";
import { LinkBtn, Panel, PBody, Tiles } from "@/components/proto/ui";
import type { StageCount } from "@/lib/pg-academic";

const LINK = "/admissions/postgraduate/stages";

export function PgStagePanel() {
  const [d, setD] = useState<{ session: string; rows: StageCount[] } | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/pg/academic/counts", { cache: "no-store", headers: { "X-Background": "1" } })
      .then(async (r) => { const j = r.ok ? await r.json() : null; if (live) { setD(j); setFailed(!j); } })
      .catch(() => { if (live) setFailed(true); });
    return () => { live = false; };
  }, []);
  const rows = d?.rows ?? [];
  const sum = (f: (r: StageCount) => number) => rows.reduce((n, r) => n + f(r), 0);
  const staged = rows.filter((r) => r.stage_code);
  const fresh = sum((r) => Number(r.fresh));
  const returning = sum((r) => (r.stage_code ? Number(r.returning) : 0));
  const extension = staged.filter((r) => r.is_extension).reduce((n, r) => n + Number(r.students), 0);
  const beyond = rows.filter((r) => !r.stage_code && r.stage_label !== "Restart required").reduce((n, r) => n + Number(r.students), 0);
  const restart = rows.filter((r) => !r.stage_code && r.stage_label === "Restart required").reduce((n, r) => n + Number(r.students), 0);
  return (
    <Panel title={`Postgraduate stages${d ? `, ${d.session}` : ""}`} right={<LinkBtn href={LINK}>Stages &amp; cycles</LinkBtn>}>
      {failed ? <PBody><div className="sub2">The stages could not be counted just now.</div></PBody> : (
        <PBody>
          <Tiles items={[
            ["Fresh", d ? fresh.toLocaleString() : "…", null, "The first stage of a cycle", `${LINK}?tab=students`],
            ["Returning", d ? returning.toLocaleString() : "…", null, "A later stage of the cycle", `${LINK}?tab=students`],
            ["On extension", d ? extension.toLocaleString() : "…", extension ? "var(--amber-ink)" : null, "700 Extension, 800 C, 900 D, 900 E", `${LINK}?tab=students`],
            ["Past the maximum period", d ? beyond.toLocaleString() : "…", beyond ? "var(--red-ink)" : null, `${restart.toLocaleString()} more closed, awaiting a restart`, `${LINK}?tab=students&stage=BEYOND`],
          ]} />
          {d ? (
            <div className="row mt-2" style={{ flexWrap: "wrap", gap: 6 }}>
              {staged.map((r) => (
                <LinkBtn key={r.stage_code} kind="ghost" href={`${LINK}?tab=students&stage=${r.stage_code}`}>{r.stage_label}: {Number(r.students).toLocaleString()}</LinkBtn>
              ))}
            </div>
          ) : null}
        </PBody>
      )}
    </Panel>
  );
}
