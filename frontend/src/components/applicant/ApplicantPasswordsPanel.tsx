"use client";
/** V710: applicant passwords on the Director of ICT's dashboard — find an undergraduate or a postgraduate applicant (the desk opens with
 *  the search) and the latest resets of both. Read after the page is drawn, so the dashboard never waits on it. */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, LinkBtn, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { PG_RESET_METHOD, RESET_METHOD } from "@/lib/applicant-password";

const UG = "/admissions/applicant-passwords";
const PG = "/admissions/postgraduate/applicant-passwords";

interface Reset { id: string; applicant: string; method: string; reason: string; reset_at: string; reset_by_name: string; jamb_key?: string | null; application_no?: string | null }

const when = (v: string) => new Date(v).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

async function latest(url: string): Promise<Reset[] | null> {
  const r = await fetch(url, { cache: "no-store", headers: { "X-Background": "1" } }).catch(() => null);
  return r && r.ok ? ((await r.json()) as Reset[]) : null;
}

export function ApplicantPasswordsPanel() {
  const router = useRouter();
  const [q, setQ] = useState("");
  const [rows, setRows] = useState<(Reset & { pg: boolean })[] | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let live = true;
    void Promise.all([latest("/api/bff/api/v1/applicant-passwords/history?limit=5"), latest("/api/bff/api/v1/pg/applicant-passwords/history?limit=5")]).then(([ug, pg]) => {
      if (!live) return;
      if (!ug && !pg) { setFailed(true); return; }
      const all = [...(ug ?? []).map((r) => ({ ...r, pg: false })), ...(pg ?? []).map((r) => ({ ...r, pg: true }))]
        .sort((a, b) => b.reset_at.localeCompare(a.reset_at)).slice(0, 6);
      setRows(all);
    });
    return () => { live = false; };
  }, []);
  const go = (desk: string) => router.push(q.trim().length >= 3 ? `${desk}?q=${encodeURIComponent(q.trim())}` : desk);
  return (
    <Panel title="Applicant passwords" right={<span className="row row--inline" style={{ gap: "var(--s-2)" }}><LinkBtn href={UG}>Undergraduate desk</LinkBtn><LinkBtn href={PG}>Postgraduate desk</LinkBtn></span>}>
      <PBody>
        <div className="row row--inline" style={{ gap: "var(--s-2)", flexWrap: "wrap" }}>
          <input className="ctl" style={{ minWidth: 280 }} value={q} placeholder="JAMB or application number, email, phone or name" aria-label="Find an applicant"
            onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") go(/^PG\//i.test(q.trim()) ? PG : UG); }} />
          <Btn kind="primary" onClick={() => go(UG)}>Find an undergraduate</Btn>
          <Btn kind="secondary" onClick={() => go(PG)}>Find a postgraduate</Btn>
        </div>
        <div className="sub2 mt-2">A reset puts the password back to the JAMB number (undergraduate) or the application number (postgraduate); the applicant chooses their own at the next sign-in.</div>
      </PBody>
      {failed ? <PBody><div className="sub2">The latest resets could not be read just now.</div></PBody>
        : rows && rows.length ? (
          <DTable noPrint pageSize={0} cols={["When", "Applicant", "Method", "By"]} rows={rows.map((r) => [
            <span key="w" className="sub2 tnum">{when(r.reset_at)}</span>,
            <span key="a">{r.applicant} <Pil kind={r.pg ? "info" : "grey"}>{r.pg ? "PG" : "UG"}</Pil><div className="sub2 tnum">{r.jamb_key ?? r.application_no ?? ""}</div></span>,
            <span key="m" className="sub2">{(r.pg ? PG_RESET_METHOD : RESET_METHOD)[r.method] ?? r.method}</span>, <span key="b" className="sub2">{r.reset_by_name}</span>])} />
        ) : rows ? <PBody><div className="sub2">No applicant&rsquo;s password has been reset yet.</div></PBody> : null}
    </Panel>
  );
}
