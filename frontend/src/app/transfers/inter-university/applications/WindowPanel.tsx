"use client";

/** V766 (D3, D4, D5, D6): the Academic Office's transfer window for a session — its state and dates, the message the public reads while
 *  it is not open, and the programmes and levels taking transfer students (each with optional places, and closable to new applications
 *  without touching those made). The window opens only with a line accepting and the session's fee published by the Bursar, a fee of
 *  nothing included; closing stops new applications only. A line whose programme was archived or merged away since it was added
 *  offers the public nothing: it is marked so, never counts as taking applications, and a window left offering none reads closed. The
 *  fee is read here, never set: it is the Bursary's. */
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { SearchSelect } from "@/components/proto/SearchSelect";
import {
  KEEPERS, countWords, dayWords, lineGone, lineWords, naira, num, offeredLines, placesOf, windowAlert, windowWords, type OfficeProgramme, type WindowLine, type WindowView,
} from "@/lib/transfer-application";
import { OFFICE, call } from "@/app/transfer/call";

const PLACES_WORDS = "Places are a whole number of 1 or more, or left blank for no limit";

const STATE_WORD: Record<string, string> = { DRAFT: "Draft: being prepared", OPEN: "Open", CLOSED: "Closed" };

export function WindowPanel({ view, programmes, sessions, office, onSession }: {
  view: WindowView; programmes: OfficeProgramme[]; sessions: { name: string; state: string }[]; office: string | null; onSession: (s: string) => void;
}) {
  const router = useRouter();
  const may = KEEPERS.includes(office ?? "");
  const [w, setW] = useState({ state: view.state ?? "DRAFT", opensOn: view.opensOn ?? "", closesOn: view.closesOn ?? "", message: view.message ?? "", note: view.note ?? "" });
  const [add, setAdd] = useState<{ programme: string; levels: number[]; places: string }>({ programme: "", levels: [], places: "" });
  const [places, setPlaces] = useState<Record<string, string>>({});
  const chosen = programmes.find((p) => p.code === add.programme) ?? null;
  const open = sessions.filter((s) => s.state === "PLANNED" || s.state === "CURRENT").map((s) => s.name);
  const [status, pill] = windowWords(view.status, view.opensOn, view.closesOn);
  const fee = view.fee ?? null;
  const lines = view.lines ?? [];
  const alert = windowAlert(view);
  const key = (l: WindowLine) => `${l.programme}:${l.level}`;
  const options = useMemo(() => programmes.map((p) => ({ value: p.code, label: p.name, sub: [p.facultyName, p.deptName].filter(Boolean).join(" · ") })), [programmes]);

  async function saveWindow() {
    const r = await call<WindowView>("PUT", `${OFFICE}/window`, {
      session: view.session, state: w.state, opensOn: w.opensOn || null, closesOn: w.closesOn || null, message: w.message.trim() || null, note: w.note.trim() || null,
    }, `Transfer window for ${view.session}: ${w.state}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    notify(`The ${view.session} transfer window is saved: ${STATE_WORD[w.state] ?? w.state}`);
    router.refresh();
  }
  async function addLines() {
    if (!chosen || !add.levels.length) return;
    const n = placesOf(add.places);
    if (n === undefined) { notifyProblem({ status: 400, title: PLACES_WORDS }); return; }
    const r = await call<WindowView>("POST", `${OFFICE}/lines`, { session: view.session, programme: chosen.code, levels: add.levels, places: n },
      `Transfer window ${view.session}: ${chosen.name} at ${add.levels.join(", ")} Level`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    notify(`${chosen.name}: ${add.levels.map((l) => `${l} Level`).join(", ")} taking transfer students in ${view.session}`);
    setAdd({ programme: "", levels: [], places: "" });
    router.refresh();
  }
  /* a places mistyped is refused here: sent, it would reach the API as null, which takes the line's limit off */
  function savePlaces(l: WindowLine, typed: string) {
    const n = placesOf(typed);
    if (n === undefined) { notifyProblem({ status: 400, title: PLACES_WORDS, detail: `“${typed.trim()}” is not a number of places` }); return; }
    void setLine(l, { places: n });
  }
  async function setLine(l: WindowLine, patch: { places?: number | null; accepting?: boolean }) {
    const body = { session: view.session, programme: l.programme, level: l.level, places: "places" in patch ? patch.places : l.places ?? null, accepting: patch.accepting ?? l.accepting };
    const r = await call<WindowView>("PUT", `${OFFICE}/lines`, body, `Transfer window ${view.session}: ${l.programmeName ?? l.programme} ${l.level} Level changed`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    notify(`${l.programmeName ?? l.programme}, ${l.level} Level: saved`);
    setPlaces((x) => { const y = { ...x }; delete y[key(l)]; return y; });
    router.refresh();
  }
  async function removeLine(l: WindowLine) {
    if (!window.confirm(`Remove ${l.programmeName ?? l.programme}, ${l.level} Level from the ${view.session} window?`)) return;
    const qs = new URLSearchParams({ session: view.session, programme: l.programme, level: String(l.level) });
    const r = await call<WindowView>("DELETE", `${OFFICE}/lines?${qs}`, undefined, `Transfer window ${view.session}: ${l.programmeName ?? l.programme} ${l.level} Level removed`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    notify(`${l.programmeName ?? l.programme}, ${l.level} Level: removed`);
    router.refresh();
  }

  return (
    <>
      <Panel title="The window" right={<span className="row row--inline row--tight"><Pil kind={pill}>{status}</Pil><span className="sub2">{view.session}</span></span>}>
        <PBody>
          {alert ? <Note kind="bad" title="Open, but offering nothing">{alert}.</Note> : null}
          <div className="sub2 mb-2">
            Students of other universities apply at <b>/transfer/apply</b> while the window is open; the sign-in page shows its line then too. The window opens only with
            a programme accepting below and the session&rsquo;s application fee published by the Bursar (a fee of nothing counts). Closing stops new applications
            only: an application already started still pays, uploads, submits and is decided.
          </div>
          <div className="grid grid--4">
            <Field id="iw-session" label="Session">
              <select id="iw-session" className="ctl" value={view.session} onChange={(e) => onSession(e.target.value)}>
                {!open.includes(view.session) ? <option value={view.session}>{view.session}</option> : null}
                {open.map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
            </Field>
            <Field id="iw-state" label="State">
              <select id="iw-state" className="ctl" value={w.state} disabled={!may} onChange={(e) => setW({ ...w, state: e.target.value })}>
                {Object.entries(STATE_WORD).map(([k, label]) => <option key={k} value={k}>{label}</option>)}
              </select>
            </Field>
            <Field id="iw-opens" label="Opens on" required={w.state === "OPEN"}>
              <input id="iw-opens" type="date" className="ctl tnum" value={w.opensOn} disabled={!may} onChange={(e) => setW({ ...w, opensOn: e.target.value })} />
            </Field>
            <Field id="iw-closes" label="Closes on" required={w.state === "OPEN"} hint="The last day applications are taken (Lagos time)">
              <input id="iw-closes" type="date" className="ctl tnum" value={w.closesOn} disabled={!may} onChange={(e) => setW({ ...w, closesOn: e.target.value })} />
            </Field>
          </div>
          <Field id="iw-message" label="What the public reads while the window is not open" hint="Plain text; a blank line starts a paragraph. Left blank, the portal's own words">
            <textarea id="iw-message" className="ctl" rows={3} maxLength={2000} value={w.message} disabled={!may} onChange={(e) => setW({ ...w, message: e.target.value })} />
          </Field>
          <Field id="iw-note" label="Note for the record">
            <input id="iw-note" className="ctl" value={w.note} disabled={!may} onChange={(e) => setW({ ...w, note: e.target.value })} maxLength={500} />
          </Field>
          <div className="row mt-2" style={{ alignItems: "center" }}>
            {may ? <Btn kind="primary" onClick={() => saveWindow()}>Save the window</Btn> : <span className="sub2">The Academic Office and the Registry set the window.</span>}
            <span className="grow" />
            {view.setAt ? <span className="sub2">Last set by {view.setByName ?? view.setOffice ?? "—"}, {dayWords(view.setAt)}</span> : null}
          </div>
        </PBody>
        <PBody>
          <KvGrid cls="grid--2" pairs={[
            ["Application fee", fee?.published ? <b key="f">{num(fee.amount) > 0 ? `${naira(fee.amount)} published` : "Published: no fee is charged"}</b>
              : <span key="f">Not published: the Bursar publishes it on Fee Setup{fee?.draftAmount != null ? ` (a draft of ${naira(fee.draftAmount)} waits)` : ""}</span>],
            ["Applications", countWords(view.counts) || "None yet"],
          ]} />
        </PBody>
      </Panel>

      <Panel title="Programmes and levels taking transfer students" right={`${offeredLines(lines)} offered of ${lines.length}`}>
        {lines.length ? (
          <DTable cols={["Programme", "Faculty · department", "Level|num", "Places", "Accepting", "Applications|num", "Approved|num", "Admitted|num", "|num"]} rows={lines.map((l) => {
            const k = key(l);
            const typed = places[k];
            return [
              <span key="p"><b>{l.programmeName ?? l.programme}</b><div className="sub2 tnum">{l.programme}</div></span>,
              <span key="f" className="sub2">{[l.facultyName ?? l.faculty, l.deptName ?? l.dept].filter(Boolean).join(" · ")}</span>,
              <span key="l" className="tnum">{l.level}</span>,
              may ? (
                <span key="pl" className="row row--inline row--tight">
                  <input aria-label={`Places for ${l.programmeName ?? l.programme} ${l.level} Level`} className="ctl tnum" style={{ maxWidth: 80 }} placeholder="No limit"
                    value={typed ?? (l.places != null ? String(l.places) : "")} onChange={(e) => setPlaces({ ...places, [k]: e.target.value })} inputMode="numeric" />
                  {typed !== undefined ? <Btn kind="ghost" size="sm" onClick={() => savePlaces(l, typed)}>Save</Btn> : null}
                </span>
              ) : <span key="pl" className="tnum">{l.places ?? "No limit"}</span>,
              may ? (
                <span key="a">
                  <label className="row row--inline row--tight" style={{ gap: 6 }}>
                    <input type="checkbox" className="chk" checked={l.accepting} onChange={(e) => void setLine(l, { accepting: e.target.checked })} />
                    <span className="sub2">{l.accepting ? "Accepting" : "Closed to new"}</span>
                  </label>
                  {lineGone(l) ? <Pil kind={lineWords(l)[1]}>{lineWords(l)[0]}</Pil> : null}
                </span>
              ) : <Pil key="a" kind={lineWords(l)[1]}>{lineWords(l)[0]}</Pil>,
              <span key="n" className="tnum">{l.applications ?? 0}</span>,
              <span key="ap" className="tnum">{l.approved ?? 0}</span>,
              <span key="ad" className="tnum">{l.admitted ?? 0}</span>,
              may ? <Btn key="x" kind="ghost" size="sm" onClick={() => removeLine(l)}>Remove</Btn> : <span key="x" />,
            ];
          })} texts={lines.map((l) => `${l.programme} ${l.programmeName ?? ""} ${l.deptName ?? ""} ${l.facultyName ?? ""}`)} />
        ) : <PBody><Note kind="info" title={`No programme takes transfer students in ${view.session} yet`}>Add one below; the window opens only with a programme accepting.</Note></PBody>}
        {may ? (
          <PBody>
            <div className="eyebrow mb-1">Add a programme</div>
            <div className="sub2 mb-1">Places are counted against the level the Head of Department recommends, at the Registry&rsquo;s approval; leave them blank for no limit. A line
              in use is closed to new applications rather than removed.</div>
            <div className="row row--inline row--tight" style={{ flexWrap: "wrap", alignItems: "flex-end" }}>
              <Field id="iw-prog" label="Programme" style={{ minWidth: 320 }}>
                <SearchSelect id="iw-prog" value={add.programme} onChange={(v) => setAdd({ programme: v, levels: [], places: add.places })} options={options} placeholder="Choose an undergraduate programme…" />
              </Field>
              <div className="field">
                <label>Levels</label>
                <div className="row row--inline row--tight" style={{ flexWrap: "wrap", minHeight: 36, alignItems: "center" }}>
                  {chosen ? chosen.levels.map((lv) => (
                    <label key={lv} className="row row--inline row--tight" style={{ gap: 4 }}>
                      <input type="checkbox" className="chk" checked={add.levels.includes(lv)}
                        onChange={(e) => setAdd({ ...add, levels: e.target.checked ? [...add.levels, lv].sort() : add.levels.filter((x) => x !== lv) })} />
                      <span>{lv}</span>
                    </label>
                  )) : <span className="sub2">Choose a programme first</span>}
                </div>
              </div>
              <Field id="iw-places" label="Places">
                <input id="iw-places" className="ctl tnum" style={{ maxWidth: 100 }} placeholder="No limit" value={add.places} onChange={(e) => setAdd({ ...add, places: e.target.value })} inputMode="numeric" />
              </Field>
              <Btn kind="primary" disabled={!chosen || !add.levels.length} onClick={() => addLines()}>Add</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>
    </>
  );
}
