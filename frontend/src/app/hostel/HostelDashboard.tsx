"use client";

/** The accommodation desk (V261): the figures of the session, the beds by status, occupancy by hall, block and room type,
 *  applications by status, hall, faculty and level, what waits at the desk, and the allocation run — preview, validate, confirm. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { Donut, HBars, VZ, vzNum } from "@/components/proto/vz";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { OCCUPANCY, WINDOW_STATE, callHostel, dayOf, pct, type Dash, type DashboardData } from "@/lib/hostel";

const OFFICERS = ["services", "housing", "registrar", "admin", "super"];
const OCC_COL: Record<string, string> = { OCCUPIED: VZ.s1, RESERVED: VZ.warn, AVAILABLE: VZ.good, MAINTENANCE: VZ.crit, OUT_OF_SERVICE: VZ.s5 };
const APP_COL: Record<string, string> = { UNDER_REVIEW: VZ.warn, APPROVED: VZ.s1, ALLOCATED: VZ.s3, CONFIRMED: VZ.good, WAITLISTED: VZ.s4, REJECTED: VZ.crit, LAPSED: VZ.crit, CORRECTION: VZ.s2 };
const APP_LABEL: Record<string, string> = { UNDER_REVIEW: "Under review", APPROVED: "Approved", ALLOCATED: "Allocated", CONFIRMED: "Confirmed", WAITLISTED: "Waitlisted", REJECTED: "Rejected", LAPSED: "Lapsed", CORRECTION: "Correction" };

export function HostelDashboard({ data, session: s, sessions, office }: { data: DashboardData; session: string; sessions: string[]; office: string | null }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const d = JSON.parse(data.dashboard) as Dash;
  const t = d.totals;
  const w = d.setting;
  const pv = data.preview;
  const may = !!office && OFFICERS.includes(office);
  const [ask, setAsk] = useState<"draw" | "lapse" | null>(null);
  const [seed, setSeed] = useState("");
  const [busy, setBusy] = useState(false);
  const q = (path: string, extra = "") => `${path}?session=${encodeURIComponent(s)}${extra}`;
  const occupancyRate = pct(t.occupied + t.reserved, t.beds);
  const [s1, s2] = s.split("/");

  async function draw() {
    setBusy(true);
    try {
      const r = await callHostel<{ allocated: number; unsuccessful: number; priority: number }>("POST", `/hostel/sessions/${s1}/${s2}/draw`, { seed: w?.allocation_method === "BALLOT" ? seed : (seed || w?.allocation_method || "METHOD") }, `Generate the hostel allocation for ${s}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`${r.data.allocated} allocated · ${r.data.unsuccessful} waitlisted · ${r.data.priority} by priority`, r.data.unsuccessful ? "warn" : "ok");
      setAsk(null); router.refresh();
    } finally { setBusy(false); }
  }
  async function lapse() {
    setBusy(true);
    try {
      const r = await callHostel<{ lapsed: number }>("POST", `/hostel/sessions/${s1}/${s2}/lapse`, {}, `Lapse expired hostel holds for ${s}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`${r.data.lapsed} hold(s) lapsed and passed on`); setAsk(null); router.refresh();
    } finally { setBusy(false); }
  }

  const HEAD = ["S/N", "Hostel", "Type", "Gender", "Beds", "Occupied", "Reserved", "Available", "Maintenance", "Occupancy %"];
  const body = () => d.byHall.map((h, i) => [i + 1, h.hall, h.kind, h.sex === "F" ? "Female" : h.sex === "M" ? "Male" : "Mixed", h.beds, h.occupied, h.reserved, h.available, h.maintenance, pct(h.occupied + h.reserved, h.beds)]);
  async function excel() { const blob = await brandedXlsx("Hostel Occupancy by Hall", HEAD, body(), { sheetName: "Occupancy", serial: docSerial("HST"), sub: s }); downloadBlob(blob, `hostel-occupancy-${s.replace("/", "-")}.xlsx`); }

  return (
    <>
      <PageHead title="Accommodation" description={`${s}. ${vzNum(t.occupied + t.reserved)} / ${vzNum(t.beds)} beds — ${occupancyRate}% occupancy. Every figure below is a door to the records it counts.`}
        actions={<>
          <Field id="ho-session" label="Session"><select id="ho-session" className="ctl" value={s} onChange={(e) => queryNav(`/hostel?session=${encodeURIComponent(e.target.value)}`)}>{(sessions.includes(s) ? sessions : [s, ...sessions]).map((n) => <option key={n} value={n}>{n}</option>)}</select></Field>
          <LinkBtn kind="secondary" href={q("/hostel/window")}>Window &amp; Rules</LinkBtn>
          <LinkBtn kind="secondary" href={q("/hostel/inventory")}>Inventory</LinkBtn>
          <LinkBtn kind="secondary" href={q("/hostel/applications")}>Applications</LinkBtn>
          <LinkBtn kind="secondary" href={q("/hostel/occupancy")}>Occupancy</LinkBtn>
          <LinkBtn kind="primary" href={q("/hostel/clearance")}>Checkout &amp; Clearance</LinkBtn>
        </>} />

      {w ? (
        <Note kind={w.state === "OPEN" ? "ok" : w.state === "ALLOCATED" ? "info" : "bad"} title={<>Window for {s} <Pil kind={WINDOW_STATE[w.state]?.[1] ?? "grey"}>{WINDOW_STATE[w.state]?.[0] ?? w.state}</Pil></>}
          action={may ? <span className="row row--inline row--tight">
            {!w.drawn_at && w.allocation_method !== "MANUAL" ? <Btn kind="primary" onClick={() => setAsk("draw")} disabled={!pv.free_beds || !pv.approved}>Generate Allocation</Btn> : null}
            <Btn kind="ghost" onClick={() => setAsk("lapse")}>Lapse expired holds</Btn>
          </span> : null}>
          <span className="blk">Fee ₦{Number(w.fee).toLocaleString()} · hold {w.hold_hours} h · {w.applications_open ? `opens ${dayOf(w.applications_open)}` : "open now"}{w.applications_close ? ` · closes ${dayOf(w.applications_close)}` : ""} · {w.allocation_method.toLowerCase().replace("_", " ")}{w.requires_review ? " · review required" : ""}{w.drawn_at ? ` · allocation made ${dayOf(w.drawn_at)}` : ""}</span>
          <span className="blk">{vzNum(pv.approved)} ready to seat · {vzNum(pv.pending_review)} awaiting review · {vzNum(pv.free_beds)} free bed(s) in {pv.rooms} room(s) of {pv.halls} hall(s) — the run would seat {vzNum(pv.will_seat)} and waitlist {vzNum(pv.will_wait)}.</span>
        </Note>
      ) : (
        <Note kind="info" title={`No window is stated for ${s}`} action={may ? <LinkBtn kind="primary" href={q("/hostel/window")}>State the window</LinkBtn> : null}>The fee, the dates, the rules and the allocation method are stated before students can apply.</Note>
      )}

      <Tiles items={[
        ["Total beds", vzNum(t.beds), null, `${vzNum(t.halls_active)} of ${vzNum(t.halls)} hostel(s) active · ${vzNum(t.rooms)} rooms`, q("/hostel/inventory")],
        ["Occupied", vzNum(t.occupied), "var(--chrome)", `${occupancyRate}% occupancy with reserved`, q("/hostel/occupancy", "&status=OCCUPIED")],
        ["Reserved", vzNum(t.reserved), t.reserved ? "var(--amber-ink)" : null, "Allocated, not yet checked in", q("/hostel/occupancy", "&status=RESERVED")],
        ["Available", vzNum(t.available), "var(--green-ink)", `${vzNum(t.rooms_available)} room(s) with a free bed`, q("/hostel/occupancy", "&status=AVAILABLE")],
        ["Under maintenance", vzNum(t.maintenance), t.maintenance ? "var(--red-ink)" : null, `${vzNum(t.out_of_service)} out of service`, q("/hostel/occupancy", "&status=MAINTENANCE")],
        ["Students accommodated", vzNum(t.students_accommodated), null, `${vzNum(t.checked_in)} checked in`, q("/hostel/occupancy", "&view=students")],
        ["Applications", vzNum(t.applications), null, `${vzNum(t.pending_review)} pending review · ${vzNum(t.approved)} approved`, q("/hostel/applications")],
        ["Allocated", vzNum(t.allocated), "var(--green-ink)", `${vzNum(t.unallocated)} unallocated · ${vzNum(t.lapsed)} lapsed`, q("/hostel/applications", "&state=ALLOCATED")],
        ["Waitlisted", vzNum(t.waitlisted), t.waitlisted ? "var(--amber-ink)" : null, "Offered a bed in list order", q("/hostel/applications", "&state=WAITLISTED")],
        ["Checked out", vzNum(t.checked_out), null, `${vzNum(t.checkouts_pending)} checkout(s) requested`, q("/hostel/clearance")],
        ["Pending clearance", vzNum(t.pending_clearance), t.pending_clearance ? "var(--amber-ink)" : null, `${vzNum(t.cleared)} cleared`, q("/hostel/clearance", "&state=PENDING")],
        ["Open maintenance", vzNum(t.maintenance_open), t.maintenance_open ? "var(--red-ink)" : null, `${vzNum(t.transfers_pending)} transfer request(s)`, q("/hostel/clearance", "&tab=maintenance")],
      ]} cls="grid--4" />

      {data.waiting.reviews || data.waiting.transfers || data.waiting.checkouts || data.waiting.clearances || data.waiting.checkins ? (
        <Panel title="Waiting at this desk">
          <DTable cols={["What", "How many|num", "|num"]} rows={[
            ["Applications to review", data.waiting.reviews, q("/hostel/applications", "&state=PENDING_REVIEW")],
            ["Students to check in", data.waiting.checkins, q("/hostel/occupancy", "&view=checkins")],
            ["Transfer requests", data.waiting.transfers, q("/hostel/clearance", "&tab=transfers")],
            ["Checkout requests", data.waiting.checkouts, q("/hostel/clearance", "&tab=checkouts")],
            ["Clearances in progress", data.waiting.clearances, q("/hostel/clearance", "&state=PENDING")],
            ["Maintenance open", data.waiting.maintenance, q("/hostel/clearance", "&tab=maintenance")],
          ].filter((r) => Number(r[1]) > 0).map((r) => [String(r[0]), <span key="n" className="tnum">{vzNum(Number(r[1]))}</span>, <LinkBtn key="o" href={String(r[2])} size="sm" kind="primary">Open</LinkBtn>])} />
        </Panel>
      ) : null}

      <div className="grid grid--2">
        <Panel title="Beds by status" right={`${vzNum(t.beds)} beds`}>
          <PBody>{d.bedStatus.length ? <Donut capLabel="occupancy" capValue={`${occupancyRate}%`} items={d.bedStatus.map((b) => ({ l: OCCUPANCY[b.status]?.[0] ?? b.status, v: Number(b.n), c: OCC_COL[b.status] ?? VZ.s5 }))} onPick={(it) => queryNav(q("/hostel/occupancy", `&status=${Object.keys(OCCUPANCY).find((k) => OCCUPANCY[k][0] === it.l) ?? ""}`))} /> : <div className="sub2">No bed on the record yet.</div>}</PBody>
        </Panel>
        <Panel title="Applications by status" right={`${vzNum(t.applications)} applications`}>
          <PBody>{d.applicationStatus.length ? <Donut capLabel="applications" capValue={vzNum(t.applications)} items={d.applicationStatus.map((a) => ({ l: APP_LABEL[a.status] ?? a.status, v: Number(a.n), c: APP_COL[a.status] ?? VZ.s5 }))} onPick={(it) => queryNav(q("/hostel/applications", `&state=${Object.keys(APP_LABEL).find((k) => APP_LABEL[k] === it.l) === "UNDER_REVIEW" ? "PENDING_REVIEW" : Object.keys(APP_LABEL).find((k) => APP_LABEL[k] === it.l) ?? ""}`))} /> : <div className="sub2">Nobody has applied for {s}.</div>}</PBody>
        </Panel>
      </div>
      <div className="grid grid--2">
        <Panel title="Occupancy by hostel" right="Occupied and reserved of beds">
          <PBody>{d.byHall.length ? <HBars items={d.byHall.map((h) => ({ l: `${h.hall} · ${h.occupied + h.reserved}/${h.beds}`, v: h.occupied + h.reserved }))} onPick={(_, i) => queryNav(q("/hostel/occupancy", `&hall=${encodeURIComponent(d.byHall[i].code)}`))} /> : <div className="sub2">No hostel yet.</div>}</PBody>
        </Panel>
        <Panel title="Occupancy by block" right="Occupied and reserved of beds">
          <PBody>{d.byBlock.length ? <HBars items={d.byBlock.map((b) => ({ l: `${b.hall} ${b.block} · ${b.occupied + b.reserved}/${b.beds}`, v: b.occupied + b.reserved }))} onPick={(_, i) => queryNav(q("/hostel/occupancy", `&hall=${encodeURIComponent(d.byHall.find((h) => h.hall === d.byBlock[i].hall)?.code ?? "")}&block=${encodeURIComponent(d.byBlock[i].block)}`))} /> : <div className="sub2">No block yet.</div>}</PBody>
        </Panel>
      </div>
      <div className="grid grid--2">
        <Panel title="Occupancy by room type" right="Taken of beds">
          <PBody>{d.byRoomType.length ? <HBars items={d.byRoomType.map((r) => ({ l: `${r.label} · ${r.occupied}/${r.beds}`, v: r.occupied }))} /> : <div className="sub2">No room yet.</div>}</PBody>
        </Panel>
        <Panel title="Students accommodated by faculty" right="Allocated beds">
          <PBody>{d.byFaculty.length ? <HBars items={d.byFaculty.map((f) => ({ l: f.faculty ?? "No faculty", v: f.accommodated }))} onPick={(_, i) => queryNav(q("/hostel/occupancy", `&view=students&fac=${encodeURIComponent(d.byFaculty[i].faculty_code ?? "")}`))} /> : <div className="sub2">Nobody accommodated yet.</div>}</PBody>
        </Panel>
      </div>
      <div className="grid grid--2">
        <Panel title="Applications by hostel preferred">
          <PBody>{d.applicationsByHall.length ? <HBars items={d.applicationsByHall.map((h) => ({ l: h.hall, v: h.n }))} /> : <div className="sub2">No application yet.</div>}</PBody>
        </Panel>
        <Panel title="Applications by faculty and level">
          <PBody>
            {d.applicationsByFaculty.length ? <HBars items={d.applicationsByFaculty.map((f) => ({ l: f.faculty, v: f.n }))} onPick={(_, i) => queryNav(q("/hostel/applications", `&fac=${encodeURIComponent(d.applicationsByFaculty[i].faculty_code ?? "")}`))} /> : <div className="sub2">No application yet.</div>}
            {d.applicationsByLevel.length ? <div className="sub2 mt-2">By level: {d.applicationsByLevel.map((l) => <Link key={String(l.level)} className="lnk" href={q("/hostel/applications", `&level=${l.level ?? ""}`)} style={{ marginRight: 10 }}>{l.level} Level · {l.n}</Link>)}</div> : null}
          </PBody>
        </Panel>
      </div>

      <Panel title="Occupancy by hostel, in figures" right={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => void excel()} disabled={!d.byHall.length}>Excel</Btn><Btn kind="ghost" onClick={() => brandedPrint("Hostel Occupancy by Hall", s, HEAD, body(), docSerial("HST"))} disabled={!d.byHall.length}>PDF</Btn></span>}>
        {d.byHall.length ? <DTable cols={["S/N|num", "Hostel", "Type|mid", "Gender|mid", "Beds|num", "Occupied|num", "Reserved|num", "Available|num", "Maintenance|num", "Occupancy|num", "|num"]} rows={d.byHall.map((h, i) => [
          <span key="sn" className="tnum sub2">{i + 1}</span>, <Link key="h" className="lnk b600" href={q("/hostel/occupancy", `&hall=${encodeURIComponent(h.code)}`)}>{h.hall}</Link>, <span key="k" className="sub2">{h.kind.toLowerCase()}</span>, <span key="x" className="sub2">{h.sex === "F" ? "Female" : h.sex === "M" ? "Male" : "Mixed"}</span>,
          <span key="b" className="tnum">{h.beds}</span>, <span key="o" className="tnum">{h.occupied}</span>, <span key="r" className="tnum">{h.reserved}</span>, <span key="a" className="tnum">{h.available}</span>, <span key="m" className="tnum">{h.maintenance}</span>,
          <span key="p" className="tnum b600">{pct(h.occupied + h.reserved, h.beds)}%</span>, <LinkBtn key="op" href={q("/hostel/occupancy", `&hall=${encodeURIComponent(h.code)}`)} size="sm">Open</LinkBtn>])} texts={d.byHall.map((h) => `${h.hall} ${h.kind}`)} /> : <PBody><div className="sub2">No hostel on the record. <Link className="lnk" href={q("/hostel/inventory")}>Create one on the inventory.</Link></div></PBody>}
      </Panel>

      {ask === "draw" ? (
        <Modal title="Generate the allocation" sub={`${s} · ${w?.allocation_method.toLowerCase().replace("_", " ")}`} onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Not now</Btn><Btn kind="primary" onClick={() => void draw()} disabled={busy || (w?.allocation_method === "BALLOT" && seed.trim().length < 6)}>{busy ? "Working…" : "Confirm and allocate"}</Btn></>}>
          <p>Before allocation: {vzNum(pv.eligible_applicants)} eligible applicant(s), {vzNum(pv.approved)} approved and ready, {vzNum(pv.pending_review)} still awaiting review, {vzNum(pv.free_beds)} free bed(s) in {pv.rooms} room(s) of {pv.halls} hall(s). The run seats {vzNum(pv.will_seat)} and waitlists {vzNum(pv.will_wait)}. Priority categories go first; every seating is validated for gender, capacity, eligibility and a double allocation, and each student is told.</p>
          {w?.allocation_method === "BALLOT" ? <Field id="ho-seed" label="Published seed" hint="At least six characters, published before the draw so anybody holding it can reproduce the order" required full><input id="ho-seed" className="ctl" value={seed} onChange={(e) => setSeed(e.target.value)} /></Field> : null}
        </Modal>
      ) : ask === "lapse" ? (
        <Modal title="Lapse expired holds" onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Not now</Btn><Btn kind="primary" onClick={() => void lapse()} disabled={busy}>Run now</Btn></>}>
          <p>Every hold whose window has passed unpaid lapses, and its bed passes to the next name on the waiting list. The clock does this every hour on its own; running it now does the same.</p>
        </Modal>
      ) : null}
    </>
  );
}
