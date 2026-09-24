import { api } from "@/lib/api";
import { receiptPurpose } from "@/lib/student-portal";
import { Note } from "@/components/proto/ui";

export const dynamic = "force-dynamic";

interface VerifyResult {
  genuine: boolean;
  name?: string; matricNo?: string | null; programme?: string | null; level?: number | null;
  amount?: number; purpose?: string; session?: string; term?: string | null; channel?: string | null;
  confirmedOn?: string | null; receiptNo?: string | null; passport?: string | null;
}

const naira = (n: number | undefined) => (n == null ? "—" : `NGN ${Number(n).toLocaleString("en-NG", { minimumFractionDigits: 2 })}`);
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");

/** /verify/receipt/[reference] — the public verification page a receipt's QR opens.
 *  It shows the authoritative Bursary record, so an altered or cloned receipt is exposed
 *  when the payer, amount or date on paper does not match what is shown here. Public. */
export default async function Page({ params, searchParams }: {
  params: Promise<{ reference: string }>; searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { reference } = await params;
  const sp = await searchParams;
  const c = typeof sp.c === "string" ? sp.c : "";
  const r = await api<VerifyResult>(`/api/v1/verify/receipt/${encodeURIComponent(reference)}?c=${encodeURIComponent(c)}`);
  const v = r.ok ? r.data : { genuine: false };
  const ok = v.genuine;

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-8) var(--s-4)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 560, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow">
            <div className="eyebrow" style={{ color: "var(--amber)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
            <div className="phead__t ink-chrome">Receipt verification</div>
          </div>
        </div>

        <div className="card__body">
          <Note kind={ok ? "ok" : "bad"} title={ok ? "Genuine — this receipt is on the Bursary's ledger" : "Not verified"}>
            {ok
              ? "Check that the payer, amount and date below match the receipt in hand."
              : "No confirmed receipt matches this code. A receipt is real only if it appears here — check the reference, or treat it as not genuine."}
          </Note>

          {ok ? (
           <>
            {v.passport ? (
              <div style={{ display: "flex", justifyContent: "center" }}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={v.passport} alt="Student passport" style={{ width: 96, height: 112, objectFit: "cover", borderRadius: "var(--r-md)", border: "1px solid var(--line)" }} />
              </div>
            ) : null}
            <div className="tablewrap">
              <table className="tbl--data">
                <tbody>
                  {[["Received from", v.name], ["Matriculation number", v.matricNo ?? "—"], ["Programme", v.programme ?? "—"],
                    ...(v.level ? [["Level", `${v.level} Level`]] : []),
                    ["Being payment for", receiptPurpose(v.purpose)], ["Session", v.session],
                    ...(v.term ? [["Semester", v.term]] : []),
                    ["Amount", naira(v.amount)],
                    ["Channel", v.channel ?? "—"], ["Confirmed on", day(v.confirmedOn)], ["Receipt number", v.receiptNo ?? "—"]].map(([k, val], i) => (
                    <tr key={i}>
                      <td className="eyebrow" style={{ whiteSpace: "nowrap", verticalAlign: "top" }}>{k}</td>
                      <td className={k === "Amount" ? "b700" : "b600"} style={{ textAlign: "right", overflowWrap: "anywhere" }}>{val ?? "—"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
           </>
          ) : null}

          <p className="sub2 ink-faint m-0 mt-1">
            This page reads the University&rsquo;s payment ledger directly; it is the record, and the printed receipt is only a view of it.
            Verified {day(new Date().toISOString())}.
          </p>
        </div>
      </div>
    </div>
  );
}
