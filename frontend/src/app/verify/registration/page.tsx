import { api } from "@/lib/api";
import { semesterName } from "@/lib/student-portal";
import { Note } from "@/components/proto/ui";

export const dynamic = "force-dynamic";

interface Course { course_code: string; title: string; units: number; entry_type: string; kind?: string }
interface RegVerify {
  genuine: boolean; name?: string; matricNo?: string | null; programme?: string | null; level?: number;
  session?: string; semester?: number; status?: string; approvedOn?: string | null; units?: number; courses?: Course[];
}

/** the academic type shown: GST, Elective or Core (Core/Required → Core), Carryover flagged */
function courseType(co: Course): string {
  if ((co.entry_type ?? "").toUpperCase() === "CARRYOVER") return "Carryover";
  const k = (co.kind ?? "").toLowerCase();
  if (k === "gst") return "GST";
  if (k === "elective") return "Elective";
  if (k === "core" || k === "compulsory" || k === "required") return "Core";
  const t = (co.entry_type ?? "").toUpperCase();
  return t === "GST" ? "GST" : t === "ELECTIVE" ? "Elective" : "Core";
}

/** /verify/registration?m=&s=&sem=&c= — the public verification of a course registration form.
 *  It shows the University's own record: the student, the approved courses, the units and the
 *  approval date, so a forged or altered form is exposed. Public. */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const g = (k: string) => (typeof sp[k] === "string" ? (sp[k] as string) : "");
  const m = g("m"), s = g("s"), sem = g("sem") || "1", c = g("c");
  const r = await api<RegVerify>(`/api/v1/verify/registration?matric=${encodeURIComponent(m)}&session=${encodeURIComponent(s)}&semester=${encodeURIComponent(sem)}&c=${encodeURIComponent(c)}`);
  const v = r.ok ? r.data : { genuine: false };
  const ok = v.genuine;
  const approved = v.approvedOn ? new Date(v.approvedOn).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—";

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-8) var(--s-4)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 600, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow">
            <div className="eyebrow" style={{ color: "var(--amber)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
            <div className="phead__t ink-chrome">Course registration verification</div>
          </div>
        </div>

        <div className="card__body">
          <Note kind={ok ? "ok" : "bad"} title={ok ? "Genuine form — this is the University's record" : "Not verified"}>
            {ok
              ? "Check that the courses, units and approval date below match the form in hand."
              : "No approved registration matches this code. Treat the form as not genuine."}
          </Note>

          {ok ? (
            <>
              <div>
                {[["Name", v.name], ["Matriculation number", v.matricNo ?? "—"], ["Programme", v.programme ?? "—"],
                  ["Level", v.level ? `${v.level} Level` : "—"], ["Session", v.session ?? "—"], ["Semester", v.semester ? semesterName(v.semester) : "—"],
                  ["Total credit units", v.units != null ? String(v.units) : "—"], ["Approved on", approved]].map(([k, val], i) => (
                  <div key={i} className="row row--between" style={{ padding: "var(--s-2) 0", borderBottom: "1px solid var(--line-2)" }}>
                    <span className="eyebrow">{k}</span>
                    <span className={k === "Name" ? "b700" : "b600"} style={{ textAlign: "right" }}>{val}</span>
                  </div>
                ))}
              </div>
              <div>
                <div className="eyebrow mb-1">Registered courses</div>
                <div className="tablewrap">
                  <table className="tbl--data">
                    <tbody>
                      {(v.courses ?? []).map((co, i) => (
                        <tr key={i}>
                          <td className="b600" style={{ whiteSpace: "nowrap" }}>{co.course_code}</td>
                          <td>{co.title}</td>
                          <td className="ink-muted" style={{ textAlign: "right", whiteSpace: "nowrap" }}>{co.units}u</td>
                          <td className="ink-muted" style={{ textAlign: "right", whiteSpace: "nowrap" }}>{courseType(co)}</td>
                        </tr>
                      ))}
                      {!(v.courses ?? []).length ? <tr><td className="ink-faint">No approved courses on record for this semester.</td></tr> : null}
                    </tbody>
                  </table>
                </div>
              </div>
            </>
          ) : null}

          <p className="sub2 ink-faint m-0 mt-1">
            This page reads the University&rsquo;s register directly. The form is a view of the register, not the register
            itself; where the printed courses, units or approval date differ from what is shown here, the record here is the
            truth. Verified {new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })}.
          </p>
        </div>
      </div>
    </div>
  );
}
