"use client";

/** The Bursar's dashboard: the users with the Bursar's role (and the Students Account Officer's) — in post or not, the account,
 *  the last sign-in, what each did in the last thirty days — and the Bursary's audit trail: every change those people made under a
 *  Bursary office (what, on which record, what changed, why) and their sign-ins, filtered and taken as Excel. Read only. */
import { useCallback, useEffect, useRef, useState } from "react";
import type { Problem } from "@/lib/api";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { actionWord, changeLines, subjectWord, trailRow, TRAIL_HEADERS, type BursaryUser, type TrailPage } from "@/lib/bursary-audit";

const API = "/api/bff/api/v1/finance/bursary";
const OFFICE: Record<string, string> = { bursar: "Bursar", studentaccounts: "Students Account Officer" };
const officeLabel = (c: string | null) => (c ? OFFICE[c] ?? c : "");
const when = (s: string | null | undefined) => (s ? new Date(s).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const day = (s: string | null | undefined) => (s ? new Date(`${s}T00:00:00`).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "");

interface Filters { person: string; office: string; kind: string; action: string; subject: string; from: string; to: string; q: string }
const NONE: Filters = { person: "", office: "", kind: "", action: "", subject: "", from: "", to: "", q: "" };

export function BursaryAudit() {
  const [users, setUsers] = useState<{ rows: BursaryUser[]; inPost: number; bursars: number } | null>(null);
  const [usersFailed, setUsersFailed] = useState<string | null>(null);
  const [f, setF] = useState<Filters>(NONE);
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [data, setData] = useState<TrailPage | null>(null);
  const [failed, setFailed] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const trailRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let live = true;
    void (async () => {
      const r = await fetch(`${API}/users`, { cache: "no-store" }).catch(() => null);
      const j = r ? await r.json().catch(() => null) : null;
      if (!live) return;
      if (!r || !r.ok) { setUsersFailed((j as { title?: string } | null)?.title ?? "The users could not be read."); return; }
      setUsers(j);
    })();
    return () => { live = false; };
  }, []);

  const url = useCallback((p: number, size: number) => {
    const qs = new URLSearchParams();
    (Object.keys(f) as (keyof Filters)[]).forEach((k) => { if (f[k]) qs.set(k, f[k]); });
    qs.set("page", String(p));
    qs.set("size", String(size));
    return `${API}/audit?${qs.toString()}`;
  }, [f]);

  useEffect(() => {
    let live = true;
    void (async () => {
      const r = await fetch(url(page, 50), { cache: "no-store" }).catch(() => null);
      const j = r ? await r.json().catch(() => null) : null;
      if (!live) return;
      if (!r || !r.ok) { setFailed((j as { title?: string } | null)?.title ?? "The trail could not be read."); return; }
      setFailed(null);
      setData(j as TrailPage);
    })();
    return () => { live = false; };
  }, [url, page]);

  const set = (k: keyof Filters, v: string) => { setF((x) => ({ ...x, [k]: v })); setPage(1); };
  const people = users ? [...new Map(users.rows.map((u) => [u.person_id, u.name])).entries()] : [];
  const pages = data ? Math.max(1, Math.ceil(data.total / data.size)) : 1;
  const filtered = Object.values(f).some(Boolean);

  async function excel() {
    if (!data?.total) return;
    setBusy(true);
    try {
      const rows: string[][] = [];
      for (let p = 1; (p - 1) * 500 < data.total && p <= 40; p++) {
        const r = await fetch(url(p, 500), { cache: "no-store" });
        const j = (await r.json().catch(() => null)) as TrailPage | null;
        if (!r.ok || !j) { notifyProblem((j ?? { status: r.status, title: "The trail could not be read" }) as unknown as Problem); return; }
        rows.push(...j.rows.map((x) => trailRow(x, officeLabel, (s) => when(s))));
        if (j.rows.length < 500) break;
      }
      const who = f.person ? people.find(([id]) => id === f.person)?.[1] : null;
      const blob = await brandedXlsx("Bursary audit trail", TRAIL_HEADERS, rows, {
        sheetName: "Audit trail", serial: docSerial("BAT"),
        sub: [who, f.office ? officeLabel(f.office) : null, f.kind === "SIGN_INS" ? "Sign-ins" : f.kind === "CHANGES" ? "Changes" : null,
          f.action ? actionWord(f.action) : null, f.subject ? subjectWord(f.subject) : null, f.from ? `from ${day(f.from)}` : null, f.to ? `to ${day(f.to)}` : null,
          f.q ? `"${f.q}"` : null].filter(Boolean).join(" · ") || "Every change and sign-in",
      });
      downloadBlob(blob, "bursary-audit-trail.xlsx");
    } finally { setBusy(false); }
  }

  function showTrailOf(person: string) {
    setF({ ...NONE, person });
    setQ("");
    setPage(1);
    trailRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  return (
    <>
      <Panel title="Users with the Bursar's role" right={users ? `${users.bursars} Bursar${users.bursars === 1 ? "" : "s"} in post · ${users.inPost} in the Bursary` : undefined}>
        {usersFailed ? <PBody><Note kind="bad" title="The users could not be read">{usersFailed}</Note></PBody> : null}
        {users && users.rows.length ? (
          <DTable pageSize={0} cols={["User", "Role", "Username", "In post", "Last sign-in", "Changes (30 days)|num", "Failed sign-ins (30 days)|num", "|num"]}
            rows={users.rows.map((u) => [
              <span key="n"><b>{u.name}</b><div className="sub2 tnum">{u.staff_number ?? "—"}{u.email ? ` · ${u.email}` : ""}</div></span>,
              <span key="o">{OFFICE[u.office_code] ?? u.office}<div className="sub2">{u.scope_kind === "platform" || u.scope_kind === "institution" ? "The University" : `${u.scope_kind} ${u.scope_id ?? ""}`}</div></span>,
              <span key="u" className="tnum">{u.username ?? <span className="sub2">no account</span>}
                {u.locked ? <div><Pil kind="bad">Locked</Pil></div> : u.must_change ? <div className="sub2">Password to change</div> : null}</span>,
              <span key="p">{u.in_post ? <Pil kind="ok">In post</Pil> : <Pil kind="grey">Ended</Pil>}
                <div className="sub2">{day(u.valid_from)}{u.valid_to ? ` to ${day(u.valid_to)}` : ""}</div></span>,
              <span key="s" className="sub2 tnum">{when(u.last_sign_in_at)}</span>,
              <span key="c" className="tnum">{Number(u.changes_30d).toLocaleString()}<div className="sub2">{u.last_change_at ? `last ${when(u.last_change_at)}` : "none yet"}</div></span>,
              <span key="f" className={`tnum${Number(u.failed_sign_ins_30d) ? " ink-red" : ""}`}>{Number(u.failed_sign_ins_30d).toLocaleString()}</span>,
              <Btn key="t" kind="ghost" size="sm" onClick={() => showTrailOf(u.person_id)}>Trail</Btn>,
            ])} />
        ) : users ? <PBody><div className="sub2">Nobody holds the Bursar&rsquo;s office or the Students Account Officer&rsquo;s. ICT grants them under Users &amp; Roles.</div></PBody> : null}
      </Panel>

      <div ref={trailRef} />
      <Panel title="Bursary audit trail" right={<Btn kind="ghost" size="sm" disabled={!data?.total || busy} busy={busy} busyLabel="Preparing…" onClick={() => void excel()}>Excel</Btn>}>
        <PBody>
          <div className="sub2">Every change the Bursary&rsquo;s users made acting as the Bursar or the Students Account Officer — what, on which record, what changed and why — and their sign-ins, newest first. It is read from the University&rsquo;s tamper-evident audit trail; nothing here can be changed.</div>
          <form className="row mt-1" onSubmit={(e) => { e.preventDefault(); set("q", q.trim()); }} style={{ flexWrap: "wrap" }}>
            <Field id="bat-person" label="User" style={{ flex: "1 1 200px" }}>
              <select id="bat-person" className="ctl" value={f.person} onChange={(e) => set("person", e.target.value)}>
                <option value="">Every user</option>
                {people.map(([id, name]) => <option key={id} value={id}>{name}</option>)}
              </select>
            </Field>
            <Field id="bat-office" label="Acting as" style={{ flex: "1 1 170px" }}>
              <select id="bat-office" className="ctl" value={f.office} onChange={(e) => set("office", e.target.value)}>
                <option value="">Either office</option>
                <option value="bursar">Bursar</option>
                <option value="studentaccounts">Students Account Officer</option>
              </select>
            </Field>
            <Field id="bat-kind" label="Show" style={{ flex: "1 1 200px" }}>
              <select id="bat-kind" className="ctl" value={f.kind} onChange={(e) => set("kind", e.target.value)}>
                <option value="">Changes and sign-ins</option>
                <option value="CHANGES">Changes only</option>
                <option value="SIGN_INS">Sign-ins only</option>
              </select>
            </Field>
            <Field id="bat-action" label="Change" style={{ flex: "1 1 130px" }}>
              <select id="bat-action" className="ctl" value={f.action} onChange={(e) => set("action", e.target.value)}>
                <option value="">Any</option>
                <option value="INSERT">Added</option>
                <option value="UPDATE">Changed</option>
                <option value="DELETE">Removed</option>
              </select>
            </Field>
            <Field id="bat-subject" label="Record" style={{ flex: "1 1 190px" }}>
              <select id="bat-subject" className="ctl" value={f.subject} onChange={(e) => set("subject", e.target.value)}>
                <option value="">Any record</option>
                {(data?.subjects ?? []).map((s) => <option key={s.subject_type} value={s.subject_type}>{subjectWord(s.subject_type)} ({Number(s.n).toLocaleString()})</option>)}
                {f.subject && !(data?.subjects ?? []).some((s) => s.subject_type === f.subject) ? <option value={f.subject}>{subjectWord(f.subject)}</option> : null}
              </select>
            </Field>
            <Field id="bat-from" label="From" style={{ flex: "0 1 150px" }}>
              <input id="bat-from" className="ctl" type="date" value={f.from} onChange={(e) => set("from", e.target.value)} />
            </Field>
            <Field id="bat-to" label="To" style={{ flex: "0 1 150px" }}>
              <input id="bat-to" className="ctl" type="date" value={f.to} onChange={(e) => set("to", e.target.value)} />
            </Field>
            <Field id="bat-q" label="Search the reason" style={{ flex: "2 1 200px" }}>
              <input id="bat-q" className="ctl" type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="A word of the reason given" />
            </Field>
            <div style={{ alignSelf: "flex-end" }} className="row row--inline row--tight">
              <Btn kind="primary" type="submit">Search</Btn>
              {filtered ? <Btn kind="ghost" onClick={() => { setF(NONE); setQ(""); setPage(1); }}>Clear</Btn> : null}
            </div>
          </form>
        </PBody>
        {data ? (
          <Tiles items={[
            ["Changes", Number(data.tiles.changes).toLocaleString(), null, filtered ? "Within these filters" : "Since the trail began"],
            ["Changes today", Number(data.tiles.changes_today).toLocaleString(), null, "Lagos time"],
            ["Sign-ins", Number(data.tiles.sign_ins).toLocaleString(), null, "Successful"],
            ["Failed sign-ins", Number(data.tiles.failed_sign_ins).toLocaleString(), Number(data.tiles.failed_sign_ins) ? "var(--red-ink)" : null, "Wrong password or locked"],
          ]} />
        ) : null}
        {failed ? <PBody><Note kind="bad" title="The trail could not be read">{failed}</Note></PBody> : null}
        {data && data.rows.length ? (
          <DTable pageSize={0} cols={["When", "Who", "What", "Details", "Reason", "From"]} rows={data.rows.map((r, i) => [
            <span key={`w${i}`} className="sub2 tnum">{when(r.at)}</span>,
            <span key="n">{r.name ?? "—"}{r.office ? <div className="sub2">as {officeLabel(r.office)}</div> : null}</span>,
            <span key="a">{r.kind === "SIGN_IN"
              ? <Pil kind={r.action === "SIGNED_IN" ? "ok" : r.action === "BAD_PASSWORD" || r.action === "LOCKED" ? "bad" : "grey"}>{actionWord(r.action)}</Pil>
              : <><b>{actionWord(r.action)}</b> {subjectWord(r.subject_type)}</>}</span>,
            <span key="d" className="sub2">{changeLines(r).map((l, j) => <div key={j}>{l}</div>)}</span>,
            <span key="r" className="sub2">{r.kind === "SIGN_IN" ? r.reason ? `as ${r.reason}` : "" : r.reason ?? "—"}</span>,
            <span key="i" className="sub2 tnum">{r.source_ip ?? "—"}</span>,
          ])} />
        ) : data && !failed ? <PBody><div className="sub2">Nothing on the trail{filtered ? " within these filters" : " yet"}.</div></PBody> : null}
        {data && pages > 1 ? (
          <PBody><div className="row row--between">
            <Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</Btn>
            <span className="sub2 tnum">Page {page} of {pages} · {data.total.toLocaleString()} in all</span>
            <Btn kind="ghost" size="sm" disabled={page >= pages} onClick={() => setPage(page + 1)}>Next</Btn>
          </div></PBody>
        ) : null}
      </Panel>
    </>
  );
}
