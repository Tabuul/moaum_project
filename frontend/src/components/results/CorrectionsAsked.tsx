"use client";

/**
 * V702: the corrections the Director of ICT asked of this desk of entry, on every sheet it reaches (the lecturer's own courses, the
 * Examinations Officer's programme) — each opened on its sheet, where the desk corrects the mark, raises the amendment or declines it.
 * The desk is told of each by email, SMS and the portal as it is asked; this is the list it works from. Nothing when none is open.
 */
import { useJson } from "@/lib/use-json";
import { LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { markWords, REASON_WORD, REQUEST_STATE_TONE, REQUEST_STATE_WORD, stageWord } from "@/lib/result-monitor";
import type { CorrectionRequest } from "./RecordDetail";

const ENTRY_DESKS = ["lecturer", "exams", "gst", "eps"];

export function CorrectionsAsked({ actingOffice }: { actingOffice: string | null }) {
  const desk = !!actingOffice && ENTRY_DESKS.includes(actingOffice);
  const { data } = useJson<CorrectionRequest[]>(desk ? "/api/bff/api/v1/results/correction-requests/mine" : null, 0);
  if (!desk || !data?.length) return null;
  return (
    <Panel title={`Corrections asked of your sheets (${data.length})`} right={<span className="sub2">From the Director of ICT</span>}>
      <PBody>
        <Note kind="bad" title="Open each on its sheet">
          At entry, correct the mark on the sheet; once published, raise the amendment through the chain; or decline it with your reason. The request closes when the corrected mark is saved or the amendment is applied.
        </Note>
        <DTable noPrint pageSize={20} cols={["Ref", "State", "Course", "Student", "As it stands", "Asked for", "Why", ""]}
          rows={data.map((q) => [q.ref, <Pil key="s" kind={REQUEST_STATE_TONE[q.state] ?? "grey"}>{REQUEST_STATE_WORD[q.state] ?? q.state}</Pil>,
            <span key="c"><b className="tnum">{q.courseCode}</b><span className="sub2" style={{ display: "block" }}>{`${q.session}, semester ${q.semester} · ${stageWord(q.stage)}`}</span></span>,
            `${q.surname.toUpperCase()}, ${q.otherNames} (${q.number ?? "—"})`,
            markWords({ ca: q.wasCa, exam: q.wasExam, total: q.wasTotal, grade: q.wasGrade, outcome: q.wasOutcome }),
            q.ca != null || q.outcome ? markWords({ ca: q.ca, exam: q.exam, outcome: q.outcome }) : "Remove or move the result",
            `${REASON_WORD[q.reasonKind] ?? q.reasonKind}: ${q.note}`,
            <LinkBtn key="o" kind="primary" href={`/results/chain?sheet=${q.sheetId}`}>Open the sheet</LinkBtn>])}
          texts={data.map((q) => `${q.ref} ${q.courseCode} ${q.surname} ${q.otherNames} ${q.number ?? ""}`)} />
      </PBody>
    </Panel>
  );
}
