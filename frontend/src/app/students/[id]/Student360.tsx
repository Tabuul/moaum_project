"use client";

/**
 * The whole record — proto/part5.html staffStudent360 and clr(): the header,
 * the three cards, the record history, and beneath them the Registry's read
 * of the biodata (proto/part23).
 *
 * Where the prototype shows figures the portal cannot yet stand behind —
 * the Bursary's ledger, a CGPA no published result supports — the card keeps
 * its shape and says so. No number here is computed from anything but the
 * record.
 */
import { reasonHeader } from "@/lib/reason";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { ClearanceRow, StudentRecord } from "@/lib/student";
import { fullName, statusLabel, statusPill } from "@/lib/student";
import type { Problem } from "@/lib/api";
import { Btn, Note, Pil, Tick, WarnIcon } from "@/components/proto/ui";
import { Field, Modal, Passport, Row, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Biodata } from "./Biodata";

const WRITERS = ["academic", "registrar", "dregistrar"];

const STATUSES = ["ACTIVE", "PROBATION", "DEFERRED", "SUSPENDED", "RUSTICATED", "WITHDRAWN",
  "EXPELLED", "TRANSFERRED_OUT", "GRADUATED", "DECEASED", "DORMANT"];

/** clr(ok, label) — the round mark and its line */
function Clr({ ok, label }: { ok: boolean; label: string }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 9 }}>
      <div
        style={{
          width: 18,
          height: 18,
          borderRadius: 9,
          background: ok ? "var(--green)" : "var(--red)",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {ok ? (
          <Tick size={10} colour="#fff" />
        ) : (
          <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="3.6" strokeLinecap="round">
            <path d="M6 6l12 12M18 6 6 18" />
          </svg>
        )}
      </div>
      <span>{label}</span>
    </div>
  );
}

function clearanceLine(c: ClearanceRow): string {
  return `${c.label} — ${c.state === "CLEARED" ? "cleared" : c.item ? c.item.toLowerCase() : "not yet cleared"}`;
}

export function Student360({
  record,
  session,
  actingOffice,
}: {
  record: StudentRecord;
  session: string;
  actingOffice: string | null;
}) {
  const router = useRouter();
  const s = record.student;
  const may = actingOffice !== null && WRITERS.includes(actingOffice);
  const [changing, setChanging] = useState(false);
  const [to, setTo] = useState("ACTIVE");
  const [instrument, setInstrument] = useState("");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [levelling, setLevelling] = useState(false);
  const [newLevel, setNewLevel] = useState(String(s.currentLevel ?? 100));
  const [levelReason, setLevelReason] = useState("");

  const cleared = record.convocationClearance.filter((c) => c.state === "CLEARED").length;
  const thisSession = record.registrations.filter((r) => r.session === session);

  async function changeStatus() {
    setBusy(true);
    setProblem(null);
    try {
      const response = await fetch(`/api/bff/api/v1/student/students/${s.id}/status`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Change of status: ${instrument}`) },
        body: JSON.stringify({ to, instrument, reason: reason || null }),
      });
      if (response.ok) {
        setChanging(false);
        setInstrument("");
        setReason("");
        router.refresh();
        return;
      }
      const json = await response.json().catch(() => null);
      setProblem(
        json && typeof json === "object" && "status" in json
          ? (json as Problem)
          : { status: response.status, title: response.statusText },
      );
    } finally {
      setBusy(false);
    }
  }

  async function correctLevel() {
    setBusy(true);
    setProblem(null);
    try {
      const response = await fetch(`/api/bff/api/v1/student/students/${s.id}/level?session=${encodeURIComponent(session)}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Level corrected to ${newLevel}: ${levelReason}`) },
        body: JSON.stringify({ level: Number(newLevel), reason: levelReason || null }),
      });
      if (response.ok) {
        setLevelling(false);
        setLevelReason("");
        router.refresh();
        return;
      }
      const json = await response.json().catch(() => null);
      setProblem(json && typeof json === "object" && "status" in json ? (json as Problem) : { status: response.status, title: response.statusText });
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <div className="card">
        <div className="card__body" style={{ flexDirection: "row", gap: 18, alignItems: "center", flexWrap: "wrap" }}>
          <Passport w={76} h={94} />
          <div style={{ flexGrow: 1, minWidth: 200 }}>
            <div style={{ fontSize: 18, fontWeight: 700, letterSpacing: "-.3px" }}>{fullName(s)}</div>
            <div className="sub2 tnum">
              {s.matricNo ?? s.admissionNo ?? "No number yet"} · {s.programmeName} · {s.currentLevel} Level · entry{" "}
              {s.entrySession} {s.entryMode.replace("_", " ")}
            </div>
          </div>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <Pil kind={statusPill(s.status)}>{statusLabel(s.status)}</Pil>
            <Btn kind="ghost" disabled={!may} onClick={() => setChanging(true)}>
              Change status
            </Btn>
            <Btn kind="ghost" disabled={!may} title="Correct the student's current level — e.g. an over-promotion by a session roll-over" onClick={() => { setNewLevel(String(s.currentLevel ?? 100)); setLevelReason(""); setProblem(null); setLevelling(true); }}>
              Correct level
            </Btn>
            <Btn kind="ghost" disabled={!may || !s.matricNo} title={s.matricNo ? "Open or reset the student's portal account with a first password they must change" : "A portal account is opened on the matriculation number"}
              onClick={async () => {
                const pw = window.prompt(`A first password for ${fullName(s)} — eight characters at least. They change it at sign-in.`);
                if (!pw) return;
                const r = await fetch(`/api/bff/api/v1/student-auth/accounts/${s.id}`, { method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Portal account opened for ${s.matricNo}`) }, body: JSON.stringify({ password: pw }) });
                const j = await r.json().catch(() => null);
                if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
                window.alert(`Portal account opened for ${s.matricNo}. The student signs in with the matriculation number and this password, and changes it at once.`);
              }}>
              Portal account
            </Btn>
          </div>
        </div>
      </div>

      <div className="sub2">
        Assembled live from the modules that own each part of it. No data is copied into the student record.
      </div>

      <div className="grid grid--3">
        <div className="card">
          <div className="card__head">
            <span className="card__title">Finance</span>
            <span className="pill pill--grey" style={{ marginLeft: "auto" }}>
              NOT YET SERVED
            </span>
          </div>
          <div className="card__body">
            <Row k="Session charge" v="—" />
            <Row k="Paid" v="—" />
            <div style={{ height: 1, background: "var(--line-2)" }} />
            <div style={{ display: "flex", justifyContent: "space-between" }}>
              <strong>Outstanding</strong>
              <strong className="tnum" style={{ color: "var(--faint)" }}>
                —
              </strong>
            </div>
            <div className="sub2">
              The Bursary&rsquo;s ledger is not on the portal yet. Nothing is shown here until the figures come from it.
            </div>
          </div>
        </div>

        <div className="card">
          <div className="card__head">
            <span className="card__title">Academic standing</span>
            <span className="pill pill--grey" style={{ marginLeft: "auto" }}>
              NO RESULT PUBLISHED
            </span>
          </div>
          <div className="card__body">
            <div style={{ display: "flex", gap: 22 }}>
              <div className="kv">
                <span className="k">CGPA</span>
                <span className="tnum" style={{ fontSize: 20, fontWeight: 700, color: "var(--faint)" }}>
                  &mdash;
                </span>
              </div>
              <div className="kv">
                <span className="k">Units registered</span>
                <span className="tnum" style={{ fontSize: 20, fontWeight: 700 }}>
                  {record.approvedUnits}
                </span>
              </div>
            </div>
            <div className="sub2">
              A CGPA follows Senate&rsquo;s approval of a result. Units are those on approved registrations.
            </div>
          </div>
        </div>

        <div className="card">
          <div className="card__head">
            <span className="card__title">Clearances</span>
            <span className="sub2" style={{ marginLeft: "auto" }}>
              {cleared} of {record.convocationClearance.length} · convocation
            </span>
          </div>
          <div className="card__body">
            {record.convocationClearance.map((c) => (
              <Clr key={c.unit} ok={c.state === "CLEARED"} label={clearanceLine(c)} />
            ))}
          </div>
        </div>
      </div>

      <div className="card">
        <div className="card__head">
          <span className="card__title">Registration</span>
          <span className="sub2" style={{ marginLeft: "auto" }}>
            {session}
          </span>
        </div>
        <div className="card__body">
          {thisSession.length === 0 ? (
            <span className="sub2">
              No registration in {session}. A registration is a record of what was submitted, and none has been.
            </span>
          ) : (
            thisSession.map((r) => (
              <Row
                key={r.id}
                k={`Semester ${r.semester} · ${statusLabel(r.status)}`}
                v={`${r.units} units${r.submittedAt ? ` · submitted ${day(r.submittedAt)}` : ""}`}
              />
            ))
          )}
        </div>
      </div>

      <div className="card">
        <div className="card__head">
          <span className="card__title">Record history</span>
          <span className="sub2" style={{ marginLeft: "auto" }}>
            Append-only · every entry attributable
          </span>
        </div>
        <div className="tablewrap">
          <table>
            <tbody>
              {record.statusHistory.length === 0 && record.decidedChanges.length === 0 ? (
                <tr>
                  <td className="sub2">
                    Nothing has changed on this record since it was created. Every change is kept, with who made it.
                  </td>
                </tr>
              ) : null}
              {record.statusHistory.map((h) => (
                <tr key={h.id}>
                  <td className="sub2 tnum" style={{ width: 120 }}>
                    {day(h.effectiveOn)}
                  </td>
                  <td>
                    {statusLabel(h.fromStatus)} &rarr; {statusLabel(h.toStatus)}
                    {h.reason ? <div className="sub2">{h.reason}</div> : null}
                  </td>
                  <td className="sub2" style={{ width: 210 }}>
                    {h.instrument}
                  </td>
                </tr>
              ))}
              {record.decidedChanges.map((c) => (
                <tr key={c.id}>
                  <td className="sub2 tnum" style={{ width: 120 }}>
                    {day(c.decidedAt)}
                  </td>
                  <td>
                    {c.label}: {c.fromValue ?? "—"} &rarr; {c.toValue}
                    <div className="sub2" style={{ color: c.state === "REFUSED" ? "var(--red-ink)" : undefined }}>
                      {c.state === "APPROVED" ? "Approved" : "Refused"} &middot; {c.decision}
                    </div>
                  </td>
                  <td className="sub2" style={{ width: 210 }}>
                    {c.evidence ?? "No evidence attached"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <Biodata record={record} may={may} />

      {levelling ? (
        <Modal
          title="Correct the level"
          sub={fullName(s)}
          onClose={() => setLevelling(false)}
          foot={
            <>
              <Btn kind="ghost" onClick={() => setLevelling(false)}>Cancel</Btn>
              <Btn kind="primary" disabled={busy || !levelReason.trim() || Number(newLevel) === (s.currentLevel ?? 0)} onClick={correctLevel}>
                Correct the level
              </Btn>
            </>
          }
        >
          <Note kind="info" title="This sets the student's current level">
            Use this to fix a wrong level — for example an over-promotion by a session roll-over. It changes only the
            current level; the reason is recorded on the audit trail in your name. It does not change registrations or
            enrolments already made.
          </Note>
          <Field id="lvl" label="Current level" full>
            <select id="lvl" className="ctl" value={newLevel} onChange={(e) => setNewLevel(e.target.value)}>
              {[100, 200, 300, 400, 500, 600].map((x) => (
                <option key={x} value={x}>{x} Level{x === (s.currentLevel ?? 0) ? " (current)" : ""}</option>
              ))}
            </select>
          </Field>
          <Field id="lvl-reason" label="Reason" hint="Why the level was wrong — recorded on the audit trail" full>
            <input id="lvl-reason" className="ctl" value={levelReason} onChange={(e) => setLevelReason(e.target.value)} placeholder="e.g. Over-promoted by the 2026/2027 roll-over; should be 200 Level" />
          </Field>
        </Modal>
      ) : null}

      {changing ? (
        <Modal
          title="Change of status"
          sub={fullName(s)}
          onClose={() => setChanging(false)}
          foot={
            <>
              <Btn kind="ghost" onClick={() => setChanging(false)}>
                Cancel
              </Btn>
              <Btn kind="primary" disabled={busy || !instrument.trim()} onClick={changeStatus}>
                Record the change
              </Btn>
            </>
          }
        >
          <Note kind="info" title="A change of status is made on an instrument">
            The Senate minute, the letter, the Registrar&rsquo;s decision. The database refuses a change that cites none,
            and the citation stays on the record.
          </Note>
          <Field id="to" label="To" full>
            <select id="to" className="ctl" value={to} onChange={(e) => setTo(e.target.value)}>
              {STATUSES.map((x) => (
                <option key={x} value={x}>
                  {statusLabel(x)}
                </option>
              ))}
            </select>
          </Field>
          <Field id="instrument" label="Instrument" hint="The minute, letter or decision this change is made on" full>
            <input id="instrument" className="ctl" value={instrument} onChange={(e) => setInstrument(e.target.value)} />
          </Field>
          <Field id="reason" label="Reason" full>
            <textarea id="reason" className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} />
          </Field>
          {s.status === "ADMITTED" && to === "ACTIVE" ? (
            <div style={{ display: "flex", gap: 9, marginTop: 6 }}>
              <WarnIcon size={17} />
              <span className="sub2">
                A student becomes ACTIVE at matriculation, in one run over the confirmed faculty lists. Doing it here
                leaves them without a matriculation number, which the database will refuse.
              </span>
            </div>
          ) : null}
        </Modal>
      ) : null}
    </>
  );
}
