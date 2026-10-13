import { api } from "@/lib/api";
import { currentInstitution } from "@/lib/document/institution-cache";
import { Note } from "@/components/proto/ui";

export const dynamic = "force-dynamic";

interface ClearanceVerify {
  genuine: boolean; codeMissing?: boolean; reference?: string; clearance?: string; session?: string; status?: string; completed_at?: string | null;
  student_name?: string; student_number?: string; programme?: string | null; faculty?: string | null; department?: string | null;
}
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");

/** /verify/clearance/{FCLR/2026/000012}?c=… — the public check of a clearance certificate (V415): with the check code its QR
 *  carries, the University's record of the clearance — the reference, the student, the session, the status, the date; without
 *  it, nothing, not even whether the reference exists. */
export default async function Page({ params, searchParams }: { params: Promise<{ ref: string[] }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { ref } = await params;
  const sp = await searchParams;
  const reference = (ref ?? []).map((x) => decodeURIComponent(x)).join("/");
  const code = typeof sp.c === "string" ? sp.c : "";
  const r = await api<ClearanceVerify>(`/api/v1/verify/clearance?${new URLSearchParams({ ref: reference, ...(code ? { c: code } : {}) }).toString()}`);
  const v: ClearanceVerify = r.ok ? r.data : { genuine: false };
  const ok = v.genuine;
  const throttled = !r.ok && r.problem.status === 429;
  const done = v.status === "CLEARED" || v.status === "COMPLETED";
  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-5) var(--s-3)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 600, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow"><div className="eyebrow" style={{ color: "var(--amber-ink)" }}>{currentInstitution().name}</div><div className="phead__t ink-chrome">Clearance verification</div></div>
        </div>
        <div className="card__body">
          <Note kind={ok && done ? "ok" : ok ? "info" : throttled || v.codeMissing ? "info" : "bad"}
            title={ok ? (done ? "Genuine — the clearance is complete on the University's record" : "Genuine, but the clearance is not complete") : throttled ? "Too many checks from this connection" : v.codeMissing ? "This certificate carries no check code" : "Not verified"}>
            {ok ? "Check that the name and number match the certificate in hand."
              : throttled ? (r.ok ? "" : r.problem.detail ?? "Try again in a few minutes.")
              : v.codeMissing ? "Scan the QR code on the certificate; it carries the check code."
              : "No clearance matches this reference and check code. Treat the certificate as not genuine."}
          </Note>
          {ok ? (
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(150px, 1fr))", gap: "var(--s-2)" }}>
              {([["Student", v.student_name ?? "—"], ["Number", v.student_number ?? "—"], ["Programme", v.programme ?? "—"], ["Faculty", v.faculty ?? "—"],
                ["Clearance", v.clearance ?? "—"], ["Session", v.session ?? "—"], ["Reference", v.reference ?? "—"], ["Status", (v.status ?? "").replace(/_/g, " ").toLowerCase()],
                ["Completed", day(v.completed_at)]] as [string, string][]).map(([k, val]) => (
                <div key={k} style={{ padding: "var(--s-2)", border: "1px solid var(--line)", borderRadius: "var(--r-sm)" }}><div className="eyebrow">{k}</div><div className="b600" style={{ textTransform: k === "Status" ? "capitalize" : undefined }}>{val}</div></div>
              ))}
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}
