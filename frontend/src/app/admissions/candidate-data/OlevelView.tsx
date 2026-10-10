"use client";

import { notifyProblem } from "@/components/proto/Toast";
/**
 * One candidate's O'Level results as JAMB sent them, sitting by sitting —
 * WAEC, NECO and NABTEB shown apart — and, for the Academic Office only,
 * the screening score they carry under the session's grading. The API
 * withholds the score from every other office and from the applicant; this
 * modal shows what it is given and says whose the score is.
 */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, Note, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { FINDING_STATE, FINDING_WORD, type OlevelDuplicateRow } from "@/lib/candidate-data";

export interface OlevelGrade { subject: string; grade: string; points: number }
export interface OlevelSitting { body: string; type: string | null; year: string | null; examNumber: string | null; subjects: OlevelGrade[]; series?: string | null }
export interface Screening { sittings: number; relevantKnown: boolean; counted: OlevelGrade[]; points: number; bonus: number; total: number }
export interface Olevel {
  session: string;
  jambKey: string;
  programme: string | null;
  programmeCode: string | null;
  sittings: OlevelSitting[];
  screening: Screening | null;
  screeningIs: string;
  /** V298: what an upload carried for this candidate that was held, skipped or flagged — theirs, or another's on their exam number */
  duplicates?: OlevelDuplicateRow[];
}

const BODY: Record<string, string> = { WAEC: "WAEC", NECO: "NECO", NABTEB: "NABTEB", OTHER: "Other body" };

export function OlevelView({ session, jambKey, name, onClose }: { session: string; jambKey: string; name: string; onClose: () => void }) {
  const [data, setData] = useState<Olevel | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);

  useEffect(() => {
    let live = true;
    (async () => {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/candidate-data/${encodeURIComponent(jambKey)}/olevel`, { cache: "no-store" });
      const body = await r.json().catch(() => null);
      if (!live) return;
      if (r.ok) setData(body as Olevel);
      else setProblem(body && typeof body === "object" && "status" in body ? (body as Problem) : { status: r.status, title: r.statusText }); notifyProblem(body && typeof body === "object" && "status" in body ? (body as Problem) : { status: r.status, title: r.statusText });
    })();
    return () => { live = false; };
  }, [session, jambKey]);

  const s = data?.screening ?? null;
  return (
    <Modal
      title={`O’Level results · ${name}`}
      sub={`${jambKey}${data?.programme ? ` · ${data.programme}` : ""} · ${data ? `${data.sittings.length} sitting${data.sittings.length === 1 ? "" : "s"}` : "reading…"}`}
      wide
      onClose={onClose}
      foot={<><span className="grow" /><Btn kind="ghost" onClick={onClose}>Close</Btn></>}
    >
      {problem ? <ProblemNotice problem={problem} /> : null}
      {data && !data.sittings.length ? (
        <Note kind="info" title="No O’Level result has been recorded for this candidate">
          Upload JAMB&rsquo;s O&rsquo;Level download above.
        </Note>
      ) : null}
      {data?.sittings.map((st, i) => (
        <div key={i} className="mb-3">
          <div className="row mb-2">
            <Pil kind="grey">{BODY[st.body] ?? st.body}</Pil>
            <b>{st.type ?? st.body}</b>
            <span className="sub2">{st.year ? `${st.year}` : ""}{st.series ? ` · ${st.series}` : ""}{st.examNumber ? ` · exam no. ${st.examNumber}` : ""}</span>
          </div>
          <DTable
            cols={["Subject", "Grade|mid", ...(s ? ["Points|num"] : [])]}
            rows={st.subjects.map((g) => [
              <span key="s">{g.subject}</span>,
              <b className="tnum" key="g">{g.grade}</b>,
              ...(s ? [<span className="tnum" key="p">{g.points}</span>] : []),
            ])}
          />
        </div>
      ))}
      {data?.duplicates?.length ? (
        <Note kind={data.duplicates.some((d) => d.state === "HELD" || d.state === "OPEN") ? "bad" : "info"} title="The duplicate check on this candidate’s O’Level uploads">
          {data.duplicates.map((d) => (
            <span key={d.id} style={{ display: "block" }}>
              <Pil kind={FINDING_WORD[d.kind][1]}>{FINDING_WORD[d.kind][0]}</Pil>{" "}
              {d.jamb_key === jambKey
                ? <>uploaded {d.exam_type_raw ?? d.exam_body} {d.exam_year ?? ""}{d.exam_number ? ` · exam no. ${d.exam_number}` : ""}{d.kind === "NUMBER_ELSEWHERE" ? ` — also on ${d.other_candidate ?? d.other_jamb_key ?? "another applicant"}` : d.other_exam_number ? ` — on record: exam no. ${d.other_exam_number}` : ""}</>
                : <>{d.candidate ?? d.jamb_key} ({d.jamb_key}) was sent this candidate&rsquo;s exam number {d.other_exam_number ?? d.exam_number ?? ""}</>}
              {" · "}<Pil kind={FINDING_STATE[d.state][1]}>{FINDING_STATE[d.state][0]}</Pil>{d.note ? ` — ${d.note}` : ""}
            </span>
          ))}
        </Note>
      ) : null}
      {data && data.sittings.length ? (
        s ? (
          <>
            <Tiles items={[
              ["Subjects counted", String(s.counted.length), null, s.relevantKnown ? "The programme’s relevant subjects" : "Every subject sat · relevant subjects not stated"],
              ["Points", String(s.points), null, "Best grade per subject, across the sittings"],
              ["Sitting bonus", String(s.bonus), null, s.sittings === 1 ? "One sitting" : `${s.sittings} sittings combined`],
              ["O’Level screening score", String(s.total), "var(--chrome)", `${data.session} grading`],
            ]} />
            <DTable
              cols={["Counted subject", "Grade|mid", "Points|num"]}
              rows={s.counted.map((g) => [<strong key="s">{g.subject}</strong>, <b className="tnum" key="g">{g.grade}</b>, <b className="tnum" key="p">{g.points}</b>])}
            />
            {!s.relevantKnown ? (
              <Note kind="info" title="Provisional: the programme’s relevant subjects are not stated">
                Until the admission settings name the O&rsquo;Level subjects relevant to {data.programme ?? "this programme"}, the best subjects of all those sat are counted.
              </Note>
            ) : null}
          </>
        ) : (
          <Note kind="info" title={`The screening score is the ${data.screeningIs}’s`}>
            Shown to nobody else, including the applicant.
          </Note>
        )
      ) : null}
    </Modal>
  );
}
