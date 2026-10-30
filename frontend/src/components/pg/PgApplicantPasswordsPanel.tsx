"use client";
/** V706: postgraduate applicant passwords on the School's dashboards — find an applicant (the desk opens with the search) and the latest
 *  resets. Read after the page is drawn, so the dashboard never waits on it. */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, LinkBtn, Panel, PBody } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

const DESK = "/admissions/postgraduate/applicant-passwords";

interface Reset { id: string; applicant: string; application_no: string; reason: string; reset_at: string; reset_by_name: string }

const when = (v: string) => new Date(v).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

export function PgApplicantPasswordsPanel() {
  const router = useRouter();
  const [q, setQ] = useState("");
  const [rows, setRows] = useState<Reset[] | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/pg/applicant-passwords/history?limit=5", { cache: "no-store", headers: { "X-Background": "1" } })
      .then(async (r) => { const j = r.ok ? ((await r.json()) as Reset[]) : null; if (live) { setRows(j); setFailed(!j); } })
      .catch(() => { if (live) setFailed(true); });
    return () => { live = false; };
  }, []);
  const go = () => router.push(q.trim().length >= 3 ? `${DESK}?q=${encodeURIComponent(q.trim())}` : DESK);
  return (
    <Panel title="Applicant passwords" right={<LinkBtn href={DESK}>Password reset desk</LinkBtn>}>
      <PBody>
        <div className="row row--inline" style={{ gap: "var(--s-2)", flexWrap: "wrap" }}>
          <input className="ctl" style={{ minWidth: 280 }} value={q} placeholder="Application number, email, phone or name" aria-label="Find a postgraduate applicant"
            onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") go(); }} />
          <Btn kind="primary" onClick={go}>Find and reset</Btn>
        </div>
        <div className="sub2 mt-2">A reset makes the password the applicant&rsquo;s application number; they choose their own at the next sign-in.</div>
      </PBody>
      {failed ? <PBody><div className="sub2">The latest resets could not be read just now.</div></PBody>
        : rows && rows.length ? (
          <DTable noPrint pageSize={0} cols={["When", "Applicant", "Reason", "By"]} rows={rows.map((r) => [
            <span key="w" className="sub2 tnum">{when(r.reset_at)}</span>,
            <span key="a">{r.applicant}<div className="sub2 tnum">{r.application_no}</div></span>,
            <span key="r" className="sub2">{r.reason}</span>, <span key="b" className="sub2">{r.reset_by_name}</span>])} />
        ) : rows ? <PBody><div className="sub2">No postgraduate applicant&rsquo;s password has been reset yet.</div></PBody> : null}
    </Panel>
  );
}
