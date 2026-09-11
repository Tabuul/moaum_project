"use client";

/**
 * What every applicant screen shares (proto/part13.html): the rail of ten
 * stages, the two-column grid, and one way of posting an act to the API and
 * refreshing the screen from what the database now says.
 */
import { useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { STAGES, type Application } from "@/lib/applicant";
import { Panel } from "@/components/proto/ui";
import { Step } from "@/components/proto/blocks";

/* stage N means milestone N is complete, so N is ticked and N+1 is in hand */
export function Rail({ a }: { a: Application }) {
  return (
    <Panel title="Your application" right={STAGES[Math.min(a.stage, 9)][0]}>
      <div style={{ padding: "4px 0" }}>
        {STAGES.map((s, i) => (
          <div key={s[0]} style={{ padding: "9px 16px", borderTop: i ? "1px solid var(--line-2)" : undefined }}>
            <Step state={a.stage >= i ? "done" : a.stage + 1 === i ? "now" : "todo"} title={s[0]} sub={s[1]} />
          </div>
        ))}
      </div>
    </Panel>
  );
}

export function TwoCol({ children }: { children: ReactNode }) {
  return <div className="grid grid--2" style={{ alignItems: "start" }}>{children}</div>;
}

export function StepList({ list }: { list: ["done" | "now" | "todo", ReactNode, ReactNode][] }) {
  return (
    <div style={{ padding: "4px 0" }}>
      {list.map((x, i) => (
        <div key={i} style={{ padding: "9px 16px", borderTop: i ? "1px solid var(--line-2)" : undefined }}>
          <Step state={x[0]} title={x[1]} sub={x[2]} />
        </div>
      ))}
    </div>
  );
}

/** one act against the applicant's own application; the screen re-reads what the database now says */
export function useAct() {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  async function act(key: string, method: "POST" | "PUT", path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(key);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/applicant${path}`, {
        method,
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) },
        body: JSON.stringify(body ?? {}),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText });
        return null;
      }
      router.refresh();
      return (j ?? {}) as Record<string, unknown>;
    } finally {
      setBusy(null);
    }
  }
  return { act, busy, problem, setProblem };
}

/**
 * Card and USSD, through whichever gateway is wired: the checkout is opened
 * against the reference this portal generated, and the gateway's signed
 * webhook confirms it as the Bursary would. While no gateway is wired the
 * button says so, and the reference is paid by transfer or at a branch.
 */
const GATEWAY_LABEL: Record<string, string> = { paystack: "Paystack", flutterwave: "Flutterwave", quickteller: "Quickteller", paydirect: "Quickteller PayDirect" };

interface Paydirect { gateway: string; billerName: string; billerCode: string; prn: string; payLink: string | null; ussd: string }

export function PayByCard({ reference, amount }: { reference: string; amount: number }) {
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [choices, setChoices] = useState<string[] | null>(null);
  const [pd, setPd] = useState<Paydirect | null>(null);
  const [checkMsg, setCheckMsg] = useState<string | null>(null);
  async function check(prn: string) {
    setBusy(true);
    setProblem(null);
    setCheckMsg(null);
    try {
      const r = await fetch("/api/bff/api/v1/payments/verify", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Checked ${prn}`) }, body: JSON.stringify({ reference: prn }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      const outcome = String((j as { outcome?: string })?.outcome ?? "");
      if (outcome === "confirmed" || outcome === "already confirmed") { window.location.reload(); return; }
      setCheckMsg("Not confirmed yet. If you have just paid, it can take a few minutes to reach the University — wait a moment and check again.");
    } finally {
      setBusy(false);
    }
  }
  async function go(gateway?: string) {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/payments/checkout", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Checkout opened for ${reference}`) }, body: JSON.stringify(gateway ? { reference, gateway } : { reference }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText });
        return;
      }
      if (j && (j as Paydirect).gateway === "paydirect") { setPd(j as Paydirect); setChoices(null); return; }
      window.location.href = String((j as { url: string }).url);
    } finally {
      setBusy(false);
    }
  }
  async function start() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/payments/gateways");
      const j = (await r.json().catch(() => null)) as Record<string, boolean> | null;
      const on = j ? Object.keys(j).filter((k) => j[k]) : [];
      if (on.length > 1) { setChoices(on); setBusy(false); return; }
      await go(on[0]);
    } catch {
      setBusy(false);
      await go();
    }
  }
  return (
    <>
      {pd ? (
        <div className="notice notice--info" style={{ marginTop: 6 }}>
          <p><b>Pay &#8358;{amount.toLocaleString()} to {pd.billerName} on Quickteller.</b></p>
          <p>Your Payment Reference Number (PRN) is <b className="tnum">{pd.prn}</b>. Enter it on any of these:</p>
          <ul style={{ margin: "6px 0 0 18px" }}>
            <li>Online: {pd.payLink ? <a href={pd.payLink} target="_blank" rel="noreferrer">{pd.payLink}</a> : <>Quickteller, biller code <b className="tnum">{pd.billerCode}</b></>}</li>
            <li>USSD: <b className="tnum">{pd.ussd}</b></li>
            <li>Any bank branch or ATM: quote biller code <b className="tnum">{pd.billerCode}</b> and the PRN.</li>
          </ul>
          <p className="sub2" style={{ marginTop: 6 }}>Keep the PRN. After you pay, use &ldquo;I&rsquo;ve paid&rdquo; below, or it is confirmed automatically once the collection reaches the University.</p>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <button type="button" className="btn btn--go btn--sm" disabled={busy} onClick={() => void check(pd.prn)}>{busy ? "Checking…" : "I've paid — check now"}</button>
            <button type="button" className="btn btn--ghost btn--sm" disabled={busy} onClick={() => setPd(null)}>Choose another way to pay</button>
          </div>
          {checkMsg ? <p className="sub2" style={{ marginTop: 6 }}>{checkMsg}</p> : null}
        </div>
      ) : choices ? (
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
          <span className="sub2">Pay &#8358;{amount.toLocaleString()} with</span>
          {choices.map((g) => <button key={g} type="button" className="btn btn--go" disabled={busy} onClick={() => void go(g)}>{GATEWAY_LABEL[g] ?? g}</button>)}
          <button type="button" className="btn btn--ghost" disabled={busy} onClick={() => setChoices(null)}>Cancel</button>
        </div>
      ) : (
        <button type="button" className="btn btn--go" disabled={busy} onClick={() => void start()}>{busy ? "Opening the checkout…" : `Pay ₦${amount.toLocaleString()} by card or USSD`}</button>
      )}
      {problem ? <div style={{ flexBasis: "100%" }}><ProblemNoticeInline problem={problem} /></div> : null}
    </>
  );
}

function ProblemNoticeInline({ problem }: { problem: Problem }) {
  return (
    <div className="notice notice--info" style={{ marginTop: 6 }}>
      <p><b>{problem.title ?? "Not now"}.</b> {problem.detail ?? ""} {problem.remedy ? <span className="sub2">{problem.remedy.message}</span> : null}</p>
    </div>
  );
}

export function when(iso: string | null | undefined): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit" });
}

export function onDay(iso: string | null | undefined): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
}

export function clock(t: string | null | undefined): string {
  return t ? String(t).slice(0, 5) : "—";
}
