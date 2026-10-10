"use client";
/** "Why is this student paying GST/EPS?" (V366): the whole answer finance.gst_eps_explain gives for one student in a session — who they
 *  are, whether a GST or EPS course requires the fee of them and why, where the payment stands, and every GST/EPS course that concerns
 *  them with where it comes from (the programme's course at their level, a carryover, the registration) and where it stands. Read by the
 *  GST and EPS offices, the Bursary, the Academic Office and ICT Support; it changes nothing. */
import { KvGrid, Note, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { COURSE_STATUS_WORD, PAY_WORD, SOURCE_WORD, naira, reasonWord, type GstEpsExplain } from "@/lib/gst";

const yes = (b: boolean | null | undefined) => (b ? "Yes" : "No");

export function GstEligibilityView({ data }: { data: GstEpsExplain }) {
  const el = data.eligibility;
  const en = data.entitlement;
  const st = data.student;
  const [pw, pk] = PAY_WORD[en.state] ?? [en.state, "grey"];
  return (
    <>
      {st ? (
        <KvGrid cls="grid--4" pairs={[
          ["Student", <b key="n">{st.surname}, {st.otherNames}</b>], ["Matric No.", <span key="m" className="tnum">{st.number ?? "—"}</span>],
          ["Programme", st.programme], ["Department", st.department ?? "—"], ["Faculty", st.faculty ?? "—"],
          ["Level", <span key="l" className="tnum">{st.level}{el.level != null && el.level !== st.level ? ` (read at ${el.level} for ${data.session})` : ""}</span>],
          ["Session", data.session], ["Semesters", data.semesters.length ? data.semesters.map((s) => `${s.number}: ${s.state.toLowerCase().replace(/_/g, " ")}`).join(" · ") : "—"],
        ]} />
      ) : null}
      <div className="grid grid--2 mt-2">
        {(["GST", "EPS"] as const).map((o) => {
          const req = o === "GST" ? el.gst_required : el.eps_required;
          const reason = o === "GST" ? el.gst_reason : el.eps_reason;
          const owed = o === "GST" ? el.gst_courses : el.eps_courses;
          const carry = o === "GST" ? el.gst_carryovers : el.eps_carryovers;
          const done = o === "GST" ? el.gst_completed : el.eps_completed;
          return (
            <Note key={o} kind={req ? "bad" : "info"} title={`${o}: ${req ? "REQUIRED" : "NOT REQUIRED"}`}>
              {reasonWord(reason)}. <span className="sub2 tnum">({reason})</span>
              <span className="sub2 mt-1" style={{ display: "block" }}>Owed: {owed.length ? owed.join(", ") : "none"} · Carryovers: {carry.length ? carry.join(", ") : "none"} · Passed: {done.length ? done.join(", ") : "none"}</span>
            </Note>
          );
        })}
      </div>
      <KvGrid cls="grid--4" pairs={[
        ["GST fee owed this session", <b key="r">{yes(el.required)}</b>],
        ["Payment", <Pil key="p" kind={pk}>{pw}</Pil>],
        ["Fee", en.stated ? naira(en.fee) : "Not stated"],
        ["Paid", en.paid ? naira(en.paid) : "—"],
        ["GST payment covers EPS", yes(el.covers_eps)],
        ["Receipt", <span key="x" className="tnum">{en.receipt_no ?? en.reference ?? "—"}</span>],
        ["Paid, not required (review)", en.review ? <Pil key="v" kind="warn">For the Bursary&rsquo;s review</Pil> : "No"],
        ["Reason for the fee", <span key="w" className="sub2">{reasonWord(el.reason)}</span>],
      ]} />
      {data.courses.length ? (
        <DTable cols={["Course", "Office|mid", "Why", "Owed this session|mid", "This session|mid", "Registered|mid"]} rows={data.courses.map((c) => {
          const [sw, sk] = COURSE_STATUS_WORD[c.status] ?? [c.status, "grey"];
          return [
            <span key="c"><b className="tnum">{c.course_code}</b><div className="sub2">{c.title} · {c.units} units · {c.level} level{c.semesters?.length ? ` · semester ${c.semesters.join(", ")}` : ""}</div></span>,
            <span key="o" className="tnum">{c.office}</span>,
            <span key="w" className="sub2">{SOURCE_WORD[c.source] ?? c.source}{c.failed_in ? ` · failed ${c.failed_in}${c.last_grade ? ` (${c.last_grade})` : ""}` : ""}{c.passed_in ? ` · passed ${c.passed_in}` : ""}</span>,
            <Pil key="d" kind={c.counts ? "warn" : "grey"}>{c.counts ? "Owed" : "Not owed"}</Pil>,
            <Pil key="s" kind={sk}>{sw}</Pil>,
            <span key="r">{yes(c.registered)}</span>,
          ];
        })} />
      ) : <div className="sub2 mt-1">No GST or EPS course concerns this student in {data.session}.</div>}
    </>
  );
}
