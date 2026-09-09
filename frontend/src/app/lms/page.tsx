import Link from "next/link";
import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import type { TeachingRow } from "@/lib/lms";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Note, Panel, PBody } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export const dynamic = "force-dynamic";

/** t/lms — the lecturer's course spaces, one per allocated offering */
export default async function LmsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope } = await loadScope(params);
  const [me, t] = await Promise.all([api<Me>("/api/v1/iam/me"), api<{ session: string; spaces: TeachingRow[] }>(`/api/v1/lms/teaching?session=${encodeURIComponent(scope.session)}`)]);
  const upload = params.tab === "upload";
  return (
    <Shell route={upload ? "r/upload" : "t/lms"} me={me.ok ? me.data : null}>
      {!t.ok ? <ProblemNotice problem={t.problem} /> : (
        <>
          <Note kind="info" title="A course space is built from the approved registrations">Students are enrolled in a space automatically when their registration is approved, and nobody else can read it. Material published here reaches only them, and every read is counted.</Note>
          <Panel title={`Your course spaces — ${t.data.session}`} right={`${t.data.spaces.length}`}>
            {t.data.spaces.length ? (
              <DTable cols={["Course", "Enrolled|mid", "Materials|mid", "Assignments|mid", "|num"]} rows={t.data.spaces.map((s) => [
                <span key="c"><strong className="tnum">{s.course_code}</strong><div className="sub2">{s.title} · {s.units} units · semester {s.semester}</div></span>,
                <span className="tnum" key="e">{s.enrolled}</span>, <span className="tnum" key="m">{s.materials}</span>, <span className="tnum" key="a">{s.assignments}</span>,
                <Link key="o" href={`/lms/${s.offering_id}${upload ? "?tab=upload" : ""}`} className="btn btn--primary btn--sm">{upload ? "Upload material" : "Open the space"}</Link>,
              ])} />
            ) : <PBody><div className="sub2">No offering is allocated to you in {t.data.session}. The Head of Department allocates courses; a space follows the allocation.</div></PBody>}
          </Panel>
        </>
      )}
    </Shell>
  );
}
