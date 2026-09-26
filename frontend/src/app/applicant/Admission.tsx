"use client";

/** The applicant's admission, in one place (V269): the congratulations and the official details, where they stand, what
 *  comes next, the acceptance fee paid once for the admission, and the tracker of the steps that concern them. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tick } from "@/components/proto/ui";
import { STATUS_KIND, dayOf, parseTracker, whenAt, type Admission, type TrackerStep } from "@/lib/screening";

export function useAdmission() {
  const [d, setD] = useState<Admission | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/applicant/me/admission", { cache: "no-store" })
      .then(async (r) => { const j = await r.json().catch(() => null); if (!live) return; if (!r.ok) setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); else setD(j as Admission); })
      .catch(() => { if (live) setProblem({ status: 0, title: "Could not read your admission." }); });
    return () => { live = false; };
  }, []);
  return { d, problem };
}

export function Tracker({ steps, compact }: { steps: TrackerStep[]; compact?: boolean }) {
  if (!steps.length) return null;
  return (
    <ol className={`plain ${compact ? "row row--tight" : "stack"}`} style={compact ? { flexWrap: "wrap", gap: 10 } : undefined}>
      {steps.map((s) => (
        <li key={s.key} className="row row--tight" style={{ gap: 8, alignItems: "center" }}>
          <span className="tnum b700" style={{ color: s.state === "done" ? "var(--green-ink)" : s.state === "failed" ? "var(--red-ink)" : s.state === "now" ? "var(--chrome)" : "var(--faint)" }}>
            {s.state === "done" ? "✓" : s.state === "failed" ? "✕" : s.state === "now" ? "→" : "○"}
          </span>
          <span className={s.state === "todo" ? "sub2" : s.state === "now" ? "b600" : ""}>{s.label}</span>
        </li>
      ))}
    </ol>
  );
}

/** the compact block on the dashboard: status, next step, tracker */
export function AdmissionProgress() {
  const { d } = useAdmission();
  if (!d || !d.offer || d.offer.decision !== "OFFERED") return null;
  return (
    <Panel title="Your admission" right={<Pil kind={STATUS_KIND(d.status) === "ok" ? "ok" : STATUS_KIND(d.status) === "bad" ? "bad" : "info"}>{d.label}</Pil>}>
      <PBody>
        <div className="row row--between">
          <span><b>{d.offer.changed_to ?? d.offer.programme}</b><div className="sub2">{d.offer.faculty ? `Faculty of ${d.offer.faculty}` : ""}{d.offer.department ? ` · ${d.offer.department}` : ""} · {d.offer.session}</div></span>
          {d.next_action ? <LinkBtn kind="primary" href={d.next_href ?? "/applicant/admission"}>{d.next_action}</LinkBtn> : null}
        </div>
        <div className="mt-2"><Tracker steps={parseTracker(d.tracker)} compact /></div>
        <div className="mt-1"><LinkBtn kind="ghost" size="sm" href="/applicant/admission">Admission progress</LinkBtn></div>
      </PBody>
    </Panel>
  );
}

/** the full page */
export function AdmissionPage() {
  const { d, problem } = useAdmission();
  if (problem) return <Note kind="bad" title="Your admission">{problem.title}</Note>;
  if (!d) return <Panel title="Your admission"><PBody><div className="sub2">Reading…</div></PBody></Panel>;
  const o = d.offer;
  const steps = parseTracker(d.tracker);
  if (!o || o.decision !== "OFFERED" || !o.decision_released_at) {
    return <Note kind="info" title={d.label}>{d.detail ?? "The Admissions Board's decision is published here and by email."}</Note>;
  }
  const kind = STATUS_KIND(d.status);
  return (
    <>
      <div className="card" style={{ borderTop: "4px solid var(--green)" }}>
        <PBody>
          <div className="row" style={{ gap: 10 }}>
            <div style={{ width: 26, height: 26, borderRadius: "var(--r-pill)", background: "var(--green)", display: "flex", alignItems: "center", justifyContent: "center" }}><Tick size={14} colour="var(--surface)" /></div>
            <span className="eyebrow ink-green">Congratulations</span>
          </div>
          <div className="phead__t" style={{ fontFamily: "var(--serif)", fontSize: "var(--t-2xl)" }}>You have been offered admission to Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
          <div className="sub2">Offer of provisional admission released {whenAt(o.decision_released_at)}{o.changed_to ? ` · programme changed to ${o.changed_to} on approval` : ""}</div>
          <div className="hr" />
          <KvGrid cls="grid--3" pairs={[
            ["Name", `${o.surname}, ${o.other_names}`], ["JAMB registration number", <span key="j" className="tnum">{o.jamb_reg_no}</span>], ["Application number", <span key="a" className="tnum">{o.application_no}</span>],
            ["Admission session", o.session], ["Faculty", o.faculty ?? "—"], ["Department", o.department ?? "—"],
            ["Programme", <b key="p">{o.changed_to ?? o.programme}</b>], ["Degree / programme type", o.degree_type ?? "—"], ["Admission type", `${o.entry_mode.replace("_", " ")} · ${o.entry_level} Level${o.decision_basis ? ` · ${o.decision_basis}` : ""}`],
            ["Admission status", <Pil key="s" kind={kind === "ok" ? "ok" : kind === "bad" ? "bad" : "info"}>{d.label}</Pil>], ["Admission number", <span key="n" className="tnum">{o.admission_no ?? "Issued when you are brought onto the register"}</span>],
            ["Matriculation number", <span key="m" className="tnum">{o.matric_no ?? "Issued after registration"}</span>],
          ]} />
        </PBody>
      </div>

      <Note kind={kind} title={d.next_action ? `Next step: ${d.next_action}` : d.label} action={d.next_action && d.next_href ? <LinkBtn kind={kind === "bad" ? "urgent" : "primary"} href={d.next_href}>{d.next_action}</LinkBtn> : null}>
        {d.detail ?? ""}
        {d.status === "SCHOOL_FEES_PENDING" || d.status === "COURSE_REGISTRATION_PENDING" ? <span className="blk"> Sign in to the student portal with your admission number{o.admission_no ? ` ${o.admission_no}` : ""} and the password you chose at application.</span> : null}
      </Note>

      <div className="grid grid--2">
        <Panel title="Progress tracker" right={`${steps.filter((s) => s.state === "done").length} of ${steps.length} done`}>
          <PBody><Tracker steps={steps} /></PBody>
        </Panel>
        <Panel title="Payments and documents" right="Acceptance fee is paid once, for the admission">
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              ["Acceptance fee", d.entitlement.paid ? <span key="e"><Pil kind="ok">PAID</Pil> <span className="sub2 tnum">{d.entitlement.reference ?? ""} · {dayOf(d.entitlement.confirmed_at)}</span></span> : <Pil key="e" kind="warn">NOT YET PAID</Pil>],
              ["Acceptance letter", o.accepted_at ? <a key="l" href="/applicant/status/letter" target="_blank" rel="noopener" className="lnk">View · download · print</a> : <span key="l" className="sub2">After acceptance</span>],
              ["Online screening", !d.screeningRequired ? <span key="s" className="sub2">Not required for your session</span> : o.cleared_at ? <Pil key="s" kind="ok">SUCCESSFUL</Pil> : <LinkBtn key="s" kind="secondary" size="sm" href="/applicant/clearance">Open the screening form</LinkBtn>],
              ["Change of programme", o.changed_to ? <span key="c">{o.changed_from} → <b>{o.changed_to}</b><div className="sub2">Your acceptance payment remained valid; it was not charged again.</div></span> : <span key="c" className="sub2">None</span>],
            ]} />
            {d.entitlement.paid ? <div className="sub2 mt-2">Whatever programme your admission ends on, the acceptance fee is never asked for a second time.</div> : null}
          </PBody>
        </Panel>
      </div>
    </>
  );
}
