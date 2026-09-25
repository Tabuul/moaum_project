"use client";

/** The application window of a session (V261): the fee and the hold, the opening and closing dates, the stay, the allocation
 *  method, who is eligible (status, level, faculty, registration, hostel debt), which kinds of hall, whether the desk reviews
 *  each application, the waiting list, and the hostel rules the student acknowledges once per version. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { METHODS, WINDOW_STATE, callHostel, type Dash, type DashboardData } from "@/lib/hostel";

const OFFICERS = ["services", "housing", "registrar", "admin", "super"];
const STATUSES = ["ADMITTED", "ACTIVE", "PROBATION", "DEFERRED", "SUSPENDED", "DORMANT"];

export function WindowScreen({ data, session: s, office }: { data: DashboardData; session: string; office: string | null }) {
  const router = useRouter();
  const d = JSON.parse(data.dashboard) as Dash;
  const w = d.setting;
  const may = !!office && OFFICERS.includes(office);
  const [busy, setBusy] = useState(false);
  const [f, setF] = useState({
    fee: w ? String(w.fee) : "", holdHours: w ? String(w.hold_hours) : "72", applicationsOpen: w?.applications_open ?? "", applicationsClose: w?.applications_close ?? "", allocationMethod: w?.allocation_method ?? "BALLOT",
    requiresReview: w?.requires_review ?? false, waitlist: w?.waitlist ?? true, maxApplications: w?.max_applications ? String(w.max_applications) : "", eligibleStatuses: w?.eligible_statuses ?? ["ACTIVE", "ADMITTED", "PROBATION"],
    eligibleLevels: (w?.eligible_levels ?? []).map(String), eligibleFaculties: w?.eligible_faculties ?? [], eligibleKinds: w?.eligible_kinds ?? [], requireRegistration: w?.require_registration ?? false, refuseHostelDebt: w?.refuse_hostel_debt ?? true,
    rules: w?.rules ?? "", stayFrom: w?.stay_from ?? "", stayTo: w?.stay_to ?? "", state: w?.state ?? "OPEN",
  });
  const [s1, s2] = s.split("/");
  const toggle = (list: string[], v: string) => (list.includes(v) ? list.filter((x) => x !== v) : [...list, v]);

  async function save(state?: string) {
    setBusy(true);
    try {
      const r = await callHostel("PUT", `/hostel/sessions/${s1}/${s2}/window`, {
        fee: Number(f.fee), holdHours: Number(f.holdHours) || 72, applicationsOpen: f.applicationsOpen || null, applicationsClose: f.applicationsClose || null, allocationMethod: f.allocationMethod, requiresReview: f.requiresReview, waitlist: f.waitlist,
        maxApplications: f.maxApplications ? Number(f.maxApplications) : null, eligibleStatuses: f.eligibleStatuses, eligibleLevels: f.eligibleLevels.map(Number), eligibleFaculties: f.eligibleFaculties, eligibleKinds: f.eligibleKinds,
        requireRegistration: f.requireRegistration, refuseHostelDebt: f.refuseHostelDebt, rules: f.rules || null, stayFrom: f.stayFrom || null, stayTo: f.stayTo || null, state: state ?? f.state,
      }, `Save the hostel window for ${s}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(state ? `Window ${state.toLowerCase()}` : "Window saved"); if (state) setF({ ...f, state }); router.refresh();
    } finally { setBusy(false); }
  }

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href={`/hostel?session=${encodeURIComponent(s)}`}>Accommodation</Link><span>›</span><strong>Window &amp; rules</strong></div>
      <PageHead title="Application window" description={`${s}. What the student sees, what makes them eligible, how beds are allocated, and the rules they acknowledge.`}
        actions={<>{w ? <Pil kind={WINDOW_STATE[w.state]?.[1] ?? "grey"}>{WINDOW_STATE[w.state]?.[0] ?? w.state}</Pil> : null}<LinkBtn kind="ghost" href={`/hostel?session=${encodeURIComponent(s)}`}>Back to the desk</LinkBtn></>} />
      {!may ? <Note kind="info" title="You are reading this window">The housing desk and Student Services change it.</Note> : null}
      {w?.drawn_at ? <Note kind="info" title="The allocation has been made">The method and the seed are on the record; the dates and the rules may still be changed for late seating and check-in.</Note> : null}

      <Panel title="Fee, dates and stay">
        <PBody>
          <div className="grid grid--3">
            <Field id="w-fee" label="Accommodation fee (₦)" required><input id="w-fee" type="number" min={0} className="ctl" value={f.fee} onChange={(e) => setF({ ...f, fee: e.target.value })} disabled={!may} /></Field>
            <Field id="w-hold" label="Hold window (hours)" hint="A bed is held this long for payment"><input id="w-hold" type="number" min={1} max={720} className="ctl" value={f.holdHours} onChange={(e) => setF({ ...f, holdHours: e.target.value })} disabled={!may} /></Field>
            <Field id="w-max" label="Maximum applications" hint="Blank for no limit"><input id="w-max" type="number" min={1} className="ctl" value={f.maxApplications} onChange={(e) => setF({ ...f, maxApplications: e.target.value })} disabled={!may} /></Field>
            <Field id="w-open" label="Applications open"><input id="w-open" type="date" className="ctl" value={f.applicationsOpen} onChange={(e) => setF({ ...f, applicationsOpen: e.target.value })} disabled={!may} /></Field>
            <Field id="w-close" label="Applications close"><input id="w-close" type="date" className="ctl" value={f.applicationsClose} onChange={(e) => setF({ ...f, applicationsClose: e.target.value })} disabled={!may} /></Field>
            <Field id="w-state" label="Window state"><select id="w-state" className="ctl" value={f.state} onChange={(e) => setF({ ...f, state: e.target.value })} disabled={!may}><option value="DRAFT">Draft — not visible</option><option value="OPEN">Open</option><option value="CLOSED">Closed</option><option value="ALLOCATED">Allocated</option></select></Field>
            <Field id="w-from" label="Stay from"><input id="w-from" type="date" className="ctl" value={f.stayFrom} onChange={(e) => setF({ ...f, stayFrom: e.target.value })} disabled={!may} /></Field>
            <Field id="w-to" label="Stay to"><input id="w-to" type="date" className="ctl" value={f.stayTo} onChange={(e) => setF({ ...f, stayTo: e.target.value })} disabled={!may} /></Field>
            <Field id="w-method" label="Allocation method"><select id="w-method" className="ctl" value={f.allocationMethod} onChange={(e) => setF({ ...f, allocationMethod: e.target.value })} disabled={!may}>{METHODS.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
          </div>
          <div className="row row--tight mt-1" style={{ gap: 18 }}>
            <label className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={f.requiresReview} onChange={(e) => setF({ ...f, requiresReview: e.target.checked })} disabled={!may} /> The desk reviews each application before allocation</label>
            <label className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={f.waitlist} onChange={(e) => setF({ ...f, waitlist: e.target.checked })} disabled={!may} /> Keep a waiting list; a lapsed bed passes to the next name</label>
          </div>
        </PBody>
      </Panel>

      <Panel title="Who is eligible" right="Enforced on the server at application and at every seating">
        <PBody>
          <div className="grid grid--2">
            <div>
              <div className="eyebrow">Student status</div>
              {STATUSES.map((st) => <label key={st} className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={f.eligibleStatuses.includes(st)} onChange={() => setF({ ...f, eligibleStatuses: toggle(f.eligibleStatuses, st) })} disabled={!may} /> {st.charAt(0) + st.slice(1).toLowerCase()}</label>)}
            </div>
            <div>
              <div className="eyebrow">Levels (none chosen = every level)</div>
              {["100", "200", "300", "400", "500", "600", "700", "800", "900"].map((l) => <label key={l} className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={f.eligibleLevels.includes(l)} onChange={() => setF({ ...f, eligibleLevels: toggle(f.eligibleLevels, l) })} disabled={!may} /> {l} Level</label>)}
            </div>
            <div>
              <div className="eyebrow">Faculties (none chosen = every faculty)</div>
              {data.faculties.map((fa) => <label key={fa.code} className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={f.eligibleFaculties.includes(fa.code)} onChange={() => setF({ ...f, eligibleFaculties: toggle(f.eligibleFaculties, fa.code) })} disabled={!may} /> {fa.name}</label>)}
            </div>
            <div>
              <div className="eyebrow">Kinds of hall open this session (none chosen = every kind)</div>
              {data.kinds.map((k) => <label key={k.code} className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={f.eligibleKinds.includes(k.code)} onChange={() => setF({ ...f, eligibleKinds: toggle(f.eligibleKinds, k.code) })} disabled={!may} /> {k.label}</label>)}
              <div className="eyebrow mt-2">Other conditions</div>
              <label className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={f.requireRegistration} onChange={(e) => setF({ ...f, requireRegistration: e.target.checked })} disabled={!may} /> Course registration for the session submitted</label>
              <label className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={f.refuseHostelDebt} onChange={(e) => setF({ ...f, refuseHostelDebt: e.target.checked })} disabled={!may} /> No unsettled hostel damage charge or uncleared stay</label>
            </div>
          </div>
          <div className="sub2 mt-1">Gender follows the hall: a hall stated for one sex only takes students of that sex, whatever the preference. A student holds one bed a session.</div>
        </PBody>
      </Panel>

      <Panel title="Hostel rules and regulations" right={w ? `Version ${w.rules_version} — a change makes a new version the student acknowledges again` : "Acknowledged once per version"}>
        <PBody>
          <Field id="w-rules" label="" full><textarea id="w-rules" className="ctl" rows={12} value={f.rules} onChange={(e) => setF({ ...f, rules: e.target.value })} disabled={!may} placeholder="The rules the student acknowledges before accepting an allocation. Leave blank to ask for no acknowledgement." /></Field>
        </PBody>
      </Panel>

      {may ? (
        <div className="row row--tight">
          <Btn kind="primary" onClick={() => void save()} disabled={busy || !f.fee}>{w ? "Save the window" : "Create the window"}</Btn>
          {w && w.state !== "OPEN" ? <Btn kind="secondary" onClick={() => void save("OPEN")} disabled={busy || !f.fee}>Save and open applications</Btn> : null}
          {w && w.state === "OPEN" ? <Btn kind="ghost" onClick={() => void save("CLOSED")} disabled={busy}>Save and close applications</Btn> : null}
        </div>
      ) : null}
    </>
  );
}
