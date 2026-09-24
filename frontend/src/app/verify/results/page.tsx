import { api } from "@/lib/api";
import { semesterName } from "@/lib/student-portal";
import { Note } from "@/components/proto/ui";

export const dynamic = "force-dynamic";

interface Row { course_code: string; title: string; units: number; total: number | null; grade: string | null; points: number | null; outcome: string | null }
interface ResultVerify {
  genuine: boolean; name?: string; matricNo?: string | null; programme?: string | null; level?: number;
  session?: string; semester?: number; gpa?: number | null; cgpa?: number | null; standing?: string | null;
  approvedOn?: string | null; senateMinute?: string | null; rows?: Row[];
}

/** /verify/results?m=&s=&sem=&c= — the public verification of a semester results statement.
 *  It shows the University's own record: the published grades, the GPA/CGPA, the class of standing
 *  and the Senate approval date, so an altered statement is exposed. Public. */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const g = (k: string) => (typeof sp[k] === "string" ? (sp[k] as string) : "");
  const m = g("m"), s = g("s"), sem = g("sem") || "1", c = g("c");
  const r = await api<ResultVerify>(`/api/v1/verify/results?matric=${encodeURIComponent(m)}&session=${encodeURIComponent(s)}&semester=${encodeURIComponent(sem)}&c=${encodeURIComponent(c)}`);
  const v = r.ok ? r.data : { genuine: false };
  const ok = v.genuine;
  const approved = v.approvedOn ? new Date(v.approvedOn).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—";
  const scoreOf = (row: Row) => row.outcome === "GRADED" ? (row.total == null ? "—" : String(row.total)) : (row.outcome ? row.outcome.charAt(0) + row.outcome.slice(1).toLowerCase() : "—");

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-8) var(--s-4)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 620, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow">
            <div className="eyebrow" style={{ color: "var(--amber)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
            <div className="phead__t ink-chrome">Semester results verification</div>
          </div>
        </div>

        <div className="card__body">
          <Note kind={ok ? "ok" : "bad"} title={ok ? "Genuine statement — this is the University's record" : "Not verified"}>
            {ok
              ? "Check that the grades, GPA and approval date below match the statement in hand."
              : "No published statement matches this code. Treat the statement as not genuine."}
          </Note>

          {ok ? (
            <>
              <div>
                {[["Name", v.name], ["Matriculation number", v.matricNo ?? "—"], ["Programme", v.programme ?? "—"],
                  ["Level", v.level ? `${v.level} Level` : "—"], ["Session", v.session ?? "—"], ["Semester", v.semester ? semesterName(v.semester) : "—"],
                  ["Semester GPA", v.gpa != null ? String(v.gpa) : "—"], ["Cumulative GPA", v.cgpa != null ? String(v.cgpa) : "—"],
                  ["Class of standing", v.standing ?? "—"], ["Approved by Senate on", v.senateMinute ? `${approved} · minute ${v.senateMinute}` : approved]].map(([k, val], i) => (
                  <div key={i} className="row row--between" style={{ padding: "var(--s-2) 0", borderBottom: "1px solid var(--line-2)" }}>
                    <span className="eyebrow">{k}</span>
                    <span className={k === "Name" ? "b700" : "b600"} style={{ textAlign: "right" }}>{val}</span>
                  </div>
                ))}
              </div>
              <div>
                <div className="eyebrow mb-1">Published grades</div>
                <div className="tablewrap">
                  <table className="tbl--data">
                    <tbody>
                      {(v.rows ?? []).map((row, i) => (
                        <tr key={i}>
                          <td className="b600" style={{ whiteSpace: "nowrap" }}>{row.course_code}</td>
                          <td>{row.title}</td>
                          <td className="ink-muted" style={{ textAlign: "right", whiteSpace: "nowrap" }}>{row.units}u</td>
                          <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>{scoreOf(row)}</td>
                          <td className={row.grade === "F" ? "b700 ink-red" : "b700"} style={{ textAlign: "right", whiteSpace: "nowrap" }}>{row.grade ?? "—"}</td>
                        </tr>
                      ))}
                      {!(v.rows ?? []).length ? <tr><td className="ink-faint">No published result on record for this semester.</td></tr> : null}
                    </tbody>
                  </table>
                </div>
              </div>
            </>
          ) : null}

          <p className="sub2 ink-faint m-0 mt-1">
            This page reads the University&rsquo;s register directly. The statement is a view of the register, not the register
            itself; where the printed grades, GPA or approval date differ from what is shown here, the record here is the
            truth. A grade that is not on a published sheet is not shown. Verified {new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })}.
          </p>
        </div>
      </div>
    </div>
  );
}
