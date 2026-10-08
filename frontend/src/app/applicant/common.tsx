"use client";

/**
 * What every applicant screen shares (proto/part13.html): the rail of ten
 * stages, the two-column grid, and one way of posting an act to the API and
 * refreshing the screen from what the database now says.
 */
import { useEffect, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { STAGES, type Application } from "@/lib/applicant";
import { Btn, Note, Panel } from "@/components/proto/ui";
import { Step } from "@/components/proto/blocks";
import { asProblem } from "@/app/student/common";
import { QuicktellerPay } from "@/components/QuicktellerPay";
import { PAY_LABEL, isQuicktellerCheckout, type QuicktellerCheckout } from "@/lib/quickteller";

/* stage N means milestone N is complete, so N is ticked and N+1 is in hand */
export function Rail({ a }: { a: Application }) {
  /* a candidate admitted from the JAMB list (V270) never had a CBT slip or score here: those two steps do not concern them */
  const fromList = !!a.decisionReleasedAt && !a.screeningSlip;
  return (
    <Panel title="Your application" right={STAGES[Math.min(a.stage, 9)][0]}>
      <div style={{ padding: "var(--s-1) 0" }}>
        {STAGES.map((s, i) => (fromList && (i === 3 || i === 4) ? null : (
          <div key={s[0]} style={{ padding: "var(--s-2) var(--s-4)", borderTop: i ? "1px solid var(--line-2)" : undefined }}>
            <Step state={a.stage >= i ? "done" : a.stage + 1 === i ? "now" : "todo"} title={s[0]} sub={s[1]} />
          </div>
        )))}
      </div>
    </Panel>
  );
}

export function TwoCol({ children }: { children: ReactNode }) {
  return <div className="grid grid--2" style={{ alignItems: "start" }}>{children}</div>;
}

export function StepList({ list }: { list: ["done" | "now" | "todo", ReactNode, ReactNode][] }) {
  return (
    <div style={{ padding: "var(--s-1) 0" }}>
      {list.map((x, i) => (
        <div key={i} style={{ padding: "var(--s-2) var(--s-4)", borderTop: i ? "1px solid var(--line-2)" : undefined }}>
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
        setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText });
        return null;
      }
      notify(reason);
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
 * webhook confirms it as the Bursary would. Pay on Quickteller (V299) sends
 * the payer to the University's biller page on quickteller.com with the
 * reference filled in, and Interswitch's report confirms it. While no gateway
 * is wired the button says so, and the reference is paid by transfer or at a branch.
 */
export function PayByCard({ reference, amount }: { reference: string; amount: number }) {
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [choices, setChoices] = useState<string[] | null>(null);
  const [qt, setQt] = useState<QuicktellerCheckout | null>(null);
  // V367: whether any gateway would take this payment, asked once: with none wired the payer is told how to pay instead of a button that cannot work
  const [wired, setWired] = useState<boolean | null>(null);
  useEffect(() => {
    let alive = true;
    void fetch(`/api/bff/api/v1/payments/gateways?reference=${encodeURIComponent(reference)}`)
      .then((r) => (r.ok ? r.json() : null))
      .then((j: Record<string, boolean> | null) => { if (alive && j) setWired(Object.values(j).some(Boolean)); })
      .catch(() => undefined);
    return () => { alive = false; };
  }, [reference]);
  async function go(gateway?: string) {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/payments/checkout", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Checkout opened for ${reference}`) }, body: JSON.stringify(gateway ? { reference, gateway } : { reference }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(asProblem(j, r)); notifyProblem(asProblem(j, r));
        return;
      }
      // Quickteller's page opens from a link in a new tab, so this page stays open to come back to
      if (isQuicktellerCheckout(j)) { setQt(j); setChoices(null); return; }
      window.location.href = String((j as { url: string }).url);
    } finally {
      setBusy(false);
    }
  }
  async function start() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/payments/gateways?reference=${encodeURIComponent(reference)}`);
      const j = (await r.json().catch(() => null)) as Record<string, boolean> | null;
      const on = j ? Object.keys(j).filter((k) => j[k]) : [];
      if (on.length > 1) { setChoices(on); setBusy(false); return; }
      await go(on[0]);
    } catch {
      setBusy(false);
      await go();
    }
  }
  if (wired === false) {
    return (
      <Note kind="info" title="Card and USSD payment is not open yet">
        Pay &#8358;{amount.toLocaleString()} against reference <b className="tnum">{reference}</b> at a bank branch or by bank transfer, quoting the reference and nothing else. The Bursary confirms it against the bank&rsquo;s record and this page shows it paid.
      </Note>
    );
  }
  return (
    <>
      {qt ? (
        <QuicktellerPay qt={qt} onClose={() => setQt(null)} />
      ) : choices ? (
        <div className="row">
          <span className="sub2">Pay &#8358;{amount.toLocaleString()} with</span>
          {choices.map((g) => <Btn key={g} kind="go" size="md" disabled={busy} onClick={() => void go(g)}>{PAY_LABEL[g] ?? g}</Btn>)}
          <Btn kind="ghost" size="md" disabled={busy} onClick={() => setChoices(null)}>Cancel</Btn>
        </div>
      ) : (
        <Btn kind="go" size="md" disabled={busy} onClick={() => void start()}>{busy ? "Opening the checkout…" : `Pay ₦${amount.toLocaleString()} by card or USSD`}</Btn>
      )}
      {problem ? <div style={{ flexBasis: "100%" }}><ProblemNoticeInline problem={problem} /></div> : null}
    </>
  );
}

function ProblemNoticeInline({ problem }: { problem: Problem }) {
  return (
    <div className="mt-2">
      <Note kind="info" title={`${problem.title ?? "Not now"}.`}>{problem.detail ?? ""} {problem.remedy ? <span className="sub2">{problem.remedy.message}</span> : null}</Note>
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
