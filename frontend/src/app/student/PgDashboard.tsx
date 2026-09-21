"use client";

/** The postgraduate student's home — its own dashboard, not a continuation of the undergraduate one.
 *  A postgraduate is read by their programme and award (PGD / Master's / Doctoral), not by a 100–600
 *  level or an honours classification. Reuses the register's data (fees, registration, results) with
 *  postgraduate framing, and links to the shared student pages. */
import Link from "next/link";
import type { Me } from "@/lib/student-portal";
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Passport } from "@/components/proto/blocks";
import { naira } from "./common";

const stageOf = (level: number) => (level >= 900 ? "MPhil / Doctoral" : level >= 800 ? "Master's degree" : "Postgraduate Diploma");

export function PgDashboard({ s }: { s: Me }) {
  const f = s.fees;
  const reg = s.registration;
  const stage = stageOf(s.entryLevel);
  const published = s.gpa.filter((g) => Number(g.published_count) > 0).length;
  const registered = reg && (reg.status === "APPROVED" || reg.status === "LOCKED");
  const feeLine = f.paidInFull ? `School fees settled in full for ${f.session}.`
    : f.balance > 0 ? `${naira(f.balance)} outstanding for ${f.session}${f.due > 0 ? "" : " — no charge stated yet"}.`
    : f.due > 0 ? `Fully paid for ${f.session}.` : `No charge stated yet for ${f.session}.`;

  return (
    <>
      <Panel title="Postgraduate student" right="Your record on the register">
        <PBody>
          <div style={{ display: "flex", gap: 18, alignItems: "flex-start", flexWrap: "wrap" }}>
            <Passport w={96} h={118} radius={6} src={s.hasPhoto ? `/api/bff/api/v1/me/passport?v=${encodeURIComponent(s.matricNo ?? s.admissionNo ?? s.id)}` : null} />
            <div style={{ flexGrow: 1, minWidth: 240 }}>
              <div style={{ fontSize: 20, fontWeight: 700, letterSpacing: "-.3px" }}>{s.name}</div>
              <div className="sub2 tnum" style={{ marginTop: 2 }}>{s.matricNo ?? s.admissionNo}</div>
              <div className="sub2" style={{ marginTop: 2 }}>{s.programme} &middot; {s.department}</div>
              <div className="sub2">{s.faculty}</div>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 10 }}>
                <span className={`pill ${s.status === "ACTIVE" ? "pill--ok" : "pill--info"}`}><span className="dot" style={{ background: s.status === "ACTIVE" ? "var(--green)" : "var(--chrome)" }} />{s.status.charAt(0) + s.status.slice(1).toLowerCase()}</span>
                <Pil kind="info">{stage}</Pil>
                <Pil kind="grey">Postgraduate · {s.entrySession}</Pil>
              </div>
            </div>
          </div>
        </PBody>
      </Panel>

      {!registered ? (
        <Note kind="info" title={`Register your courses for ${f.session}`} action={<Link href="/student/registration" className="btn btn--primary btn--sm">Course registration</Link>}>
          {f.paidInFull || f.balance === 0 ? "Your fees are in order — register the courses your programme carries this semester." : `${feeLine} Registration for a semester opens once its fees are met.`}
        </Note>
      ) : (
        <Note kind="ok" title={`Registered for ${f.session}`} action={<Link href="/student/results" className="btn btn--ghost btn--sm">My results</Link>}>
          {feeLine}
        </Note>
      )}

      <Tiles items={[
        ["Programme", stage, null, s.programme],
        ["Registration", registered ? "Approved" : reg ? reg.status.charAt(0) + reg.status.slice(1).toLowerCase() : "Not started", registered ? "var(--green-ink)" : null, f.session],
        ["Fees", f.balance > 0 ? naira(f.balance) : f.paidInFull ? "Settled" : "—", f.balance > 0 ? "var(--red-ink)" : f.paidInFull ? "var(--green-ink)" : null, f.balance > 0 ? "Outstanding" : "This session"],
        ["Results", published ? `${published} semester${published === 1 ? "" : "s"}` : "None yet", null, "Published to you"],
      ]} />

      <Panel title="Postgraduate desks" right={s.name}>
        <PBody>
          <div style={{ display: "grid", gap: 8, gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))" }}>
            <Link href="/student/registration" className="btn btn--ghost btn--sm">Course registration</Link>
            <Link href="/student/fees" className="btn btn--ghost btn--sm">Fees &amp; payments</Link>
            <Link href="/student/results" className="btn btn--ghost btn--sm">My results</Link>
            <Link href="/student/exams" className="btn btn--ghost btn--sm">Examinations</Link>
            <Link href="/student/biodata" className="btn btn--ghost btn--sm">Bio-data</Link>
            <Link href="/student/transcript" className="btn btn--ghost btn--sm">Transcript</Link>
          </div>
          <div className="sub2" style={{ marginTop: 8 }}>
            Supervision, seminars and the thesis examination will appear here as the postgraduate studies module is added.
          </div>
        </PBody>
      </Panel>
    </>
  );
}
