import { api } from "@/lib/api";
import { semesterName } from "@/lib/student-portal";
import { Note } from "@/components/proto/ui";

export const dynamic = "force-dynamic";

interface Course { course_code: string; title: string; units: number; entry_type: string }
interface ExamVerify {
  genuine: boolean; name?: string; matricNo?: string | null; programme?: string | null; level?: number;
  session?: string; semester?: number; cleared?: boolean | null; photo?: string | null; courses?: Course[];
}

/** /verify/exam?m=&s=&sem=&c= — the public verification of a student's examination card.
 *  It shows the University's own record: the name, PHOTO (checked against the face at the hall) and
 *  the courses, so a cloned or altered card is exposed. Public. */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const g = (k: string) => (typeof sp[k] === "string" ? (sp[k] as string) : "");
  const m = g("m"), s = g("s"), sem = g("sem") || "1", c = g("c");
  const r = await api<ExamVerify>(`/api/v1/verify/exam?matric=${encodeURIComponent(m)}&session=${encodeURIComponent(s)}&semester=${encodeURIComponent(sem)}&c=${encodeURIComponent(c)}`);
  const v = r.ok ? r.data : { genuine: false };
  const ok = v.genuine;

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-5) var(--s-3)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 600, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow">
            <div className="eyebrow" style={{ color: "var(--amber)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
            <div className="phead__t ink-chrome">Examination card verification</div>
          </div>
        </div>

        <div className="card__body">
          <Note kind={ok ? "ok" : "bad"} title={ok ? "Genuine card — this is the University's record" : "Not verified"}>
            {ok
              ? "Check that the face below matches the candidate, and the courses match the card in hand."
              : "No examination card matches this code. Treat the card as not genuine, and refuse admission."}
          </Note>

          {ok ? (
            <>
              {/* identity sits beside the photo so the photo's right side is not wasted on a phone */}
              <div className="row row--top" style={{ gap: "var(--s-3)", flexWrap: "nowrap" }}>
                {v.photo ? (
                  /* eslint-disable-next-line @next/next/no-img-element */
                  <img src={v.photo} alt="Candidate photograph" style={{ width: 76, height: 92, objectFit: "cover", border: "1px solid var(--line)", borderRadius: "var(--r-sm)", flexShrink: 0 }} />
                ) : <div className="sub2 ink-faint" style={{ width: 76, height: 92, border: "1px dashed var(--field)", borderRadius: "var(--r-sm)", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>No photo</div>}
                <div className="grow">
                  <div className="b700 t-lg" style={{ lineHeight: 1.25 }}>{v.name}</div>
                  <div className="tnum mt-1" style={{ overflowWrap: "anywhere" }}>{v.matricNo ?? "—"}</div>
                  <div className="t-sm ink-muted mt-1">{v.programme ?? "—"}</div>
                  <div className="t-sm ink-muted">{v.level ? `${v.level} Level` : "—"}</div>
                </div>
              </div>
              {/* short facts as compact cells — two or three to a row, never a stretched full-width line */}
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(110px, 1fr))", gap: "var(--s-2)" }}>
                {([["Session", v.session ?? "—"], ["Semester", v.semester ? semesterName(v.semester) : "—"], ["Cleared", v.cleared ? "Yes" : "No"]] as [string, string][]).map(([k, val], i) => (
                  <div key={i} className="kv" style={{ border: "1px solid var(--line-2)", borderRadius: "var(--r-md)", padding: "var(--s-2) var(--s-3)", background: "var(--bg)" }}>
                    <span className="k">{k}</span>
                    <span className="v" style={{ color: k === "Cleared" ? (v.cleared ? "var(--green-ink)" : "var(--red-deep)") : undefined }}>{val}</span>
                  </div>
                ))}
              </div>
              <div>
                <div className="eyebrow mb-1">Courses to sit</div>
                <div className="tablewrap">
                  <table className="tbl--data">
                    <tbody>
                      {(v.courses ?? []).map((co, i) => (
                        <tr key={i}>
                          <td className="b600" style={{ whiteSpace: "nowrap", verticalAlign: "top" }}>{co.course_code}</td>
                          <td style={{ verticalAlign: "top" }}>{co.title}</td>
                          <td className="ink-muted" style={{ textAlign: "right", whiteSpace: "nowrap", verticalAlign: "top" }}>{co.units}u</td>
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
            This page reads the University&rsquo;s register directly. The photograph is the one captured at admission; the
            invigilator admits a candidate only when the face matches it and this card verifies. Verified {new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })}.
          </p>
        </div>
      </div>
    </div>
  );
}
