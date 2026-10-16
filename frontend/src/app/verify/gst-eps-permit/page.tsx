import { api } from "@/lib/api";
import { semesterName } from "@/lib/student-portal";
import { Note, Pil } from "@/components/proto/ui";
import { loadInstitution } from "@/lib/document/institution-server";
import { scheduled, slotDate, slotTime, slotVenue, TO_BE_SCHEDULED, type PermitCourse } from "@/lib/gst-eps-permit";

export const dynamic = "force-dynamic";

interface PermitVerify {
  genuine: boolean; status: "VALID" | "INVALID" | "REVOKED" | "NOT_FOUND"; reference?: string; name?: string; matricNo?: string | null;
  programme?: string | null; level?: number; session?: string; semester?: number; photo?: string | null; courses?: PermitCourse[];
  reason?: string; revokedAt?: string;
}

const WORDS: Record<PermitVerify["status"], [string, string]> = {
  VALID: ["Valid permit — this is the University's record", "Check that the face below matches the candidate, and that the paper being sat is one of the courses listed."],
  INVALID: ["Not valid now", "This permit was issued, but it may not be used now."],
  REVOKED: ["Permit withdrawn", "The GST or EPS office withdrew this permit. Refuse admission and refer the candidate to the office."],
  NOT_FOUND: ["Not verified", "No GST & EPS permit matches this code. Treat the permit as not genuine and refuse admission."],
};

/** /verify/gst-eps-permit?r=&c= — the public verification of a GST & EPS examination permit (V492): the University's record now,
 *  by the permit's number and the signed code its QR carries — valid with the name, photograph and the GST and EPS courses, withdrawn,
 *  no longer valid, or not found. Public. */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const g = (k: string) => (typeof sp[k] === "string" ? (sp[k] as string) : "");
  const [inst, r] = await Promise.all([
    loadInstitution(),
    api<PermitVerify>(`/api/v1/verify/gst-eps-permit?r=${encodeURIComponent(g("r"))}&c=${encodeURIComponent(g("c"))}`, { anonymous: true }),
  ]);
  const v: PermitVerify = r.ok ? r.data : { genuine: false, status: "NOT_FOUND" };
  const ok = v.status === "VALID";
  const [title, line] = WORDS[v.status] ?? WORDS.NOT_FOUND;

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-5) var(--s-3)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 640, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={inst.logoUrl ? `/api/bff${inst.logoUrl}` : "/crest.png"} alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow">
            <div className="eyebrow" style={{ color: "var(--amber-ink)" }}>{inst.name}</div>
            <div className="phead__t ink-chrome">GST &amp; EPS examination permit verification</div>
          </div>
        </div>

        <div className="card__body">
          <Note kind={ok ? "ok" : "bad"} title={title}>
            {line}
            {v.status === "INVALID" && v.reason ? ` ${v.reason}` : ""}
            {v.status === "REVOKED" && v.revokedAt ? ` Withdrawn on ${new Date(v.revokedAt).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })}.` : ""}
          </Note>

          {v.genuine ? (
            <div className="row row--top" style={{ gap: "var(--s-3)", flexWrap: "nowrap" }}>
              {ok ? (v.photo ? (
                /* eslint-disable-next-line @next/next/no-img-element */
                <img src={v.photo} alt="Candidate photograph" style={{ width: 76, height: 92, objectFit: "cover", border: "1px solid var(--line)", borderRadius: "var(--r-sm)", flexShrink: 0 }} />
              ) : <div className="sub2 ink-faint" style={{ width: 76, height: 92, border: "1px dashed var(--field)", borderRadius: "var(--r-sm)", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>No photo</div>) : null}
              <div className="grow">
                <div className="b700 t-lg" style={{ lineHeight: 1.25 }}>{v.name}</div>
                <div className="tnum mt-1" style={{ overflowWrap: "anywhere" }}>{v.matricNo ?? "—"}</div>
                <div className="t-sm ink-muted mt-1">{v.programme ?? "—"}{v.level ? ` · ${v.level} Level` : ""}</div>
                <div className="t-sm ink-muted">{v.session} · {v.semester ? `${semesterName(v.semester)} semester` : ""}</div>
                <div className="t-sm mt-1"><span className="ink-muted">Permit number </span><span className="tnum b600">{v.reference}</span> <Pil kind={ok ? "ok" : "bad"}>{v.status}</Pil></div>
              </div>
            </div>
          ) : null}

          {ok ? (
            <div>
              <div className="eyebrow mb-1">GST and EPS courses on the approved registration</div>
              <div className="tablewrap" tabIndex={0}>
                <table className="tbl--data">
                  <tbody>
                    {(v.courses ?? []).map((co, i) => (
                      <tr key={i}>
                        <td className="b600" style={{ whiteSpace: "nowrap", verticalAlign: "top" }}>{co.course_code}<div className="sub2">{co.course_type}</div></td>
                        <td style={{ verticalAlign: "top" }}>{co.title}<div className="sub2">{scheduled(co) ? `${slotDate(co)} · ${slotTime(co)} · ${slotVenue(co)}` : TO_BE_SCHEDULED}</div></td>
                        <td className="ink-muted" style={{ textAlign: "right", whiteSpace: "nowrap", verticalAlign: "top" }}>{co.units}u</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          ) : null}

          <p className="sub2 ink-faint m-0 mt-1">
            The invigilator admits a candidate to a GST or EPS paper only when the face matches this photograph and the paper is listed. Verified {new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })}.
          </p>
        </div>
      </div>
    </div>
  );
}
