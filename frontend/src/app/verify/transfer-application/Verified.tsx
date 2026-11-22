import { api } from "@/lib/api";
import { Note } from "@/components/proto/ui";
import { verifyApiPath } from "@/lib/transfer-application";

type V = { genuine: boolean } & Record<string, string | number | boolean | null | undefined>;
const day = (iso: unknown) => (iso ? new Date(String(iso)).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "Africa/Lagos" }) : "—");

/** V766: the public verification of an inter-university transfer application's acknowledgement — the QR on the paper opens the
 *  University's record of the submission, checked by the code the API signed. It attests that the application was submitted, never a
 *  state or a decision. The API is asked with the number in its query (verifyApiPath): an encoded slash in its path is refused. */
export async function Verified({ no, code }: { no: string; code: string }) {
  const r = no ? await api<V>(verifyApiPath(no, code), { anonymous: true }) : null;
  const v: V = r?.ok ? r.data : { genuine: false };
  const ok = v.genuine === true;
  const rows: [string, string][] = ok ? [
    ["Application number", String(v.application_no ?? "")], ["Applicant", String(v.applicant_name ?? "")], ["Programme applied for", String(v.programme ?? "")],
    ["Level applied for", v.level ? `${v.level} Level` : ""], ["Present university", String(v.university ?? "")], ["Session", String(v.session ?? "")],
    ["Submitted on", day(v.submitted_on)],
  ] : [];
  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-5) var(--s-3)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 600, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow"><div className="eyebrow" style={{ color: "var(--amber-ink)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div><div className="phead__t ink-chrome">Inter-university transfer application verification</div></div>
        </div>
        <div className="card__body">
          <Note kind={ok ? "ok" : "bad"} title={ok ? "Genuine — this application was submitted to the University" : "Not verified"}>
            {ok ? "The acknowledgement in hand matches the University's record of the submission below. It is not an offer of admission."
              : "No submitted transfer application matches this number and code. Treat the acknowledgement as not genuine."}
          </Note>
          {ok ? (
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", gap: "var(--s-2)" }}>
              {rows.map(([k, val]) => (
                <div key={k} style={{ padding: "var(--s-2)", border: "1px solid var(--line)", borderRadius: "var(--r-sm)" }}><div className="eyebrow">{k}</div><div className="b600">{val || "—"}</div></div>
              ))}
            </div>
          ) : null}
          <div className="sub2 mt-3">Only publicly disclosed details are shown: the application&rsquo;s progress and any decision are not.</div>
        </div>
      </div>
    </div>
  );
}

/** a query value as one string */
export function one(x: string | string[] | undefined): string {
  return typeof x === "string" ? x : Array.isArray(x) ? x[0] ?? "" : "";
}
