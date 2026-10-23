"use client";

/**
 * The student's GST & EPS examination permit (V492): the GST and EPS courses on the submitted course registration for the
 * semester, as the API chose them, each under its own heading, with the examination's date, time and venue where the timetable
 * sets them (TO BE SCHEDULED until then); the permit viewed, downloaded or printed; or why it is not available, with the way to
 * put it right. It sits apart from the examination card, which keeps every registered course, and is issued on the card's own
 * terms — courses registered and school fees paid — and the GST fee (V589).
 */
import type { ReactNode } from "react";
import { KvGrid, LinkBtn, Note, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { semesterName } from "@/lib/student-portal";
import { paymentRemedy, permitSections, permitStatusLabel, permitSummary, registrationRemedy, slotDate, slotTime, slotVenue, type PermitState } from "@/lib/gst-eps-permit";
import { PermitActions } from "../CardActions";
import { shownCode } from "@/lib/course-code";

function CourseTables({ v }: { v: PermitState }) {
  // the S/N runs on from the GST courses into the EPS courses
  const sections = permitSections(v.courses).map((sec, i, all) => ({ ...sec, from: all.slice(0, i).reduce((k, x) => k + x.courses.length, 0) }));
  return (
    <>
      {sections.map((sec) => (
        <div key={sec.type} className="mt-2">
          <div className="eyebrow mb-1">{sec.title}</div>
          <DTable cols={["S/N|num", "Course", "Unit|num", "Type|mid", "Date", "Time", "Venue"]} rows={sec.courses.map((c, j) => {
            const n = sec.from + j + 1;
            const pending = (t: string) => (t === "TO BE SCHEDULED" ? <span className="sub2 ink-faint">{t}</span> : <span className="tnum">{t}</span>);
            return [
              <span key="n" className="tnum">{n}</span>,
              <Two key="c" a={shownCode(c.course_code)} b={c.title} />,
              <span key="u" className="tnum">{c.units}</span>,
              <Pil key="t" kind={c.course_type === "GST" ? "info" : "ok"}>{c.course_type}</Pil>,
              <span key="d">{pending(slotDate(c))}</span>,
              <span key="h">{pending(slotTime(c))}</span>,
              <span key="v">{c.bar ? <Pil kind="bad" title={c.bar.replace(/^[A-Z_]+: /, "")}>Barred: attendance</Pil> : pending(slotVenue(c))}</span>,
            ];
          })} />
        </div>
      ))}
      <div className="sub2 mt-2">{permitSummary(v)}</div>
    </>
  );
}

export function GstEpsPermit({ v, semesters }: { v: PermitState; semesters: number[] }) {
  const sem = semesterName(v.semester);
  const st = v.student;
  const status = permitStatusLabel(v);
  const remedies: ReactNode[] = [];
  if (registrationRemedy(v.code)) remedies.push(<LinkBtn key="r" kind="primary" href="/student/register">BACK TO COURSE REGISTRATION</LinkBtn>);
  if (paymentRemedy(v.code) === "GST") remedies.push(<LinkBtn key="g" kind="primary" href="/student/gst">GST FEE</LinkBtn>);
  if (paymentRemedy(v.code) === "FEES") remedies.push(<LinkBtn key="f" kind="primary" href="/student/fees">FEES & PAYMENTS</LinkBtn>);
  const approved = v.registration?.status === "APPROVED" || v.registration?.status === "LOCKED";
  return (
    <>
      {semesters.length > 1 ? (
        <div className="row row--inline" style={{ gap: 8, flexWrap: "wrap" }}>
          {semesters.map((n) => (
            <LinkBtn key={n} kind={n === v.semester ? "secondary" : "ghost"} href={`/student/exams/gst-eps-permit?semester=${n}`}>{`${semesterName(n).toUpperCase()} SEMESTER`}</LinkBtn>
          ))}
        </div>
      ) : null}

      {!v.available ? (
        <Note kind={v.code === "GST_EPS_PERMIT_REVOKED" ? "bad" : "info"} title="GST & EPS EXAMINATION PERMIT · NOT AVAILABLE"
          action={remedies.length ? <div className="row row--inline" style={{ gap: 8, flexWrap: "wrap" }}>{remedies}</div> : undefined}>
          {v.reason}
        </Note>
      ) : (
        <Note kind="ok" title="Your GST & EPS examination permit is ready">
          It lists only the GST and EPS courses on your course registration for {v.session} {sem.toLowerCase()} semester. Bring it, with your student I.D. card, to every GST and EPS examination. Your examination card is separate.
        </Note>
      )}

      <Panel title={`GST & EPS EXAMINATION PERMIT · ${v.session} · ${sem} semester`} right={<Pil kind={v.available ? "ok" : v.code === "GST_EPS_PERMIT_REVOKED" ? "bad" : "grey"}>{status}</Pil>}>
        <PBody>
          <KvGrid cls="grid--3" pairs={[
            ["Name", st.name],
            ["Matriculation number", st.matricNo ?? st.number ?? "—"],
            ...(st.jambNo ? [["JAMB registration number", st.jambNo] as [string, string]] : []),
            ["Faculty", st.faculty ?? "—"],
            ["Department", st.department ?? "—"],
            ["Programme", st.programme ?? "—"],
            ["Level", `${v.registration?.level ?? st.level ?? "—"} Level`],
            ["Permit number", v.permit?.reference ?? (v.available ? "Given when you first view the permit" : "—")],
          ]} />
          {approved && v.courses.length ? <CourseTables v={v} /> : null}
          {v.available ? <div className="mt-2"><PermitActions session={v.session} semester={v.semester} /></div> : null}
          {v.permit && v.permit.status !== "REVOKED" ? (
            <div className="sub2 mt-2">Viewed {v.permit.viewed} · downloaded {v.permit.downloaded} · printed {v.permit.printed}. Viewing or printing it again gives the same permit, with the courses your registration carries now.</div>
          ) : null}
        </PBody>
      </Panel>
    </>
  );
}
