"use client";
/** V471: the School of Postgraduate Studies' programme structure counted on its dashboards (catalogue.pg_structure_summary),
 *  each count opening the list it counts, with the structure's quick actions. Read after the page is drawn, so the dashboard
 *  never waits on it. */
import { useEffect, useState } from "react";
import { LinkBtn, Panel, PBody, Tiles } from "@/components/proto/ui";

interface Summary {
  programmes: number; programmes_with_courses: number; programmes_without_courses: number; courses: number; active_courses: number;
  inactive_courses: number; unbound_pg_courses: number; multi_programme_courses: number; multi_department_courses: number; issues: number;
}

export function PgStructurePanel() {
  const [s, setS] = useState<Summary | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/catalogue/structure/pg-summary", { cache: "no-store", headers: { "X-Background": "1" } })
      .then(async (r) => { const j = r.ok ? ((await r.json()) as Summary) : null; if (live) { setS(j); setFailed(!j); } })
      .catch(() => { if (live) setFailed(true); });
    return () => { live = false; };
  }, []);
  const n = (v: number | undefined) => (s ? Number(v ?? 0).toLocaleString() : "…");
  return (
    <Panel title="Programme structure" right={<span className="row row--inline row--tight">
      <LinkBtn href="/catalogue/structure">Programme structure</LinkBtn>
      <LinkBtn href="/catalogue/all">Manage courses</LinkBtn>
      <LinkBtn href="/admissions/postgraduate/courses">Import courses</LinkBtn>
      <LinkBtn href="/catalogue/structure/checks">Structure checks</LinkBtn>
    </span>}>
      {failed ? <PBody><div className="sub2">The structure&rsquo;s counts could not be read just now.</div></PBody> : (
        <PBody>
          <Tiles items={[
            ["PG programmes", n(s?.programmes), null, `${n(s?.programmes_with_courses)} with courses`, "/catalogue/structure/programmes"],
            ["Programmes without courses", n(s?.programmes_without_courses), s && s.programmes_without_courses ? "var(--red-ink)" : null, "Their students find nothing to register", "/catalogue/structure/programmes?empty=true"],
            ["PG courses", n(s?.courses), null, "Bound to a postgraduate programme", "/catalogue/all"],
            ["Active courses", n(s?.active_courses), null, "Live in the structure", "/catalogue/all?state=LIVE"],
            ["Inactive courses", n(s?.inactive_courses), s && s.inactive_courses ? "var(--amber-ink)" : null, "Ended but still bound", "/catalogue/all?state=ENDED"],
            ["Courses without a programme", n(s?.unbound_pg_courses), s && s.unbound_pg_courses ? "var(--amber-ink)" : null, "700 to 900 level, in no structure", "/catalogue/all?unbound=true"],
            ["Across several programmes", n(s?.multi_programme_courses), null, `${n(s?.multi_department_courses)} across several departments`, "/catalogue/all?sort=programmes&dir=desc"],
            ["Structure problems", n(s?.issues), s && s.issues ? "var(--red-ink)" : null, "Found by the structure checks", "/catalogue/structure/checks"],
          ]} />
        </PBody>
      )}
    </Panel>
  );
}
