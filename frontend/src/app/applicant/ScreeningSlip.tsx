"use client";

/**
 * The Post-UTME examination slip on screen (V260): the candidate, the batch, the day, the reporting
 * time, the centre, the room, the seat and the workstation, the examination's instructions, and the
 * QR the door scans — the same facts the PDF carries, so a phone held up at the door is enough.
 */
import { useEffect, useState } from "react";
import { at, putmeVerifyPath, reportingTime, type Application } from "@/lib/applicant";
import { KvGrid, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Passport } from "@/components/proto/blocks";
import QRCode from "qrcode";
import { Rail, clock, onDay } from "./common";

const ATTEND: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  NOT_CHECKED_IN: ["Not yet checked in", "grey"], CHECKED_IN: ["Checked in", "info"], PRESENT: ["Present", "ok"], ABSENT: ["Absent", "bad"], DISQUALIFIED: ["Disqualified", "bad"],
};

export function Screening({ a }: { a: Application }) {
  const slip = a.screeningSlip;
  const [qr, setQr] = useState<string | null>(null);
  useEffect(() => {
    if (!slip?.token) return;
    let live = true;
    QRCode.toDataURL(`${window.location.origin}${putmeVerifyPath(slip.token)}`, { errorCorrectionLevel: "M", margin: 1, width: 220 }).then((u) => { if (live) setQr(u); }).catch(() => undefined);
    return () => { live = false; };
  }, [slip?.token]);

  if (!at(a, 3) || !slip) {
    return (
      <>
        <Note kind="info" title="Your examination schedule has not been published yet">
          Batches are published once applications close and every eligible candidate is placed. You will be notified by email and SMS, and the slip will appear here.
        </Note>
        <Rail a={a} />
      </>
    );
  }
  const passport = a.documents.find((d) => d.kind === "PASSPORT");
  const postponed = slip.batchState === "POSTPONED" || slip.batchState === "CANCELLED";
  const sat = at(a, 4) || slip.examStatus === "COMPLETED";
  const att = ATTEND[slip.attendance ?? "NOT_CHECKED_IN"] ?? ATTEND.NOT_CHECKED_IN;
  return (
    <>
      {postponed ? (
        <Note kind="bad" title={slip.batchState === "POSTPONED" ? "Your batch has been postponed" : "Your batch has been cancelled"}>
          A new date will be published and you will be told by email and SMS. This slip is not valid for the door until then.
        </Note>
      ) : (
        <Note kind={sat ? "ok" : "info"} title={sat ? `You sat the examination on ${onDay(slip.heldOn)}` : `Report at ${reportingTime(slip)} on ${onDay(slip.heldOn)} with this slip and a valid identification document`}
          action={<span className="row row--inline row--tight">{at(a, 4) ? <LinkBtn kind="primary" href="/applicant/score">See your screening result</LinkBtn> : null}<a href="/applicant/screening/slip" target="_blank" rel="noopener" className="btn btn--ghost btn--sm">Download slip (PDF)</a></span>}>
          {sat ? "This slip is kept for your records. Your score is on the screening result page once it is released." : `You will not be admitted into the hall without both. Check-in closes when your batch begins at ${clock(slip.startsAt)}.`}
        </Note>
      )}
      <Panel title={slip.examName ?? "Post-UTME examination slip"} right={a.applicationNo}>
        <PBody>
          <div className="row row--top" style={{ gap: "var(--s-5)" }}>
            <Passport w={84} h={104} src={passport ? `/api/bff/api/v1/applicant/me/documents/${passport.id}/content` : a.jambPassport ?? null} alt="Your passport photograph" />
            <div style={{ flexGrow: 1, minWidth: 220 }}>
              <div className="phead__t" style={{ fontFamily: "var(--serif)" }}>{a.name}</div>
              <div className="sub2">{a.applicationNo} &middot; JAMB {a.jambKey}</div>
              <div className="sub2">{a.programme ?? "—"}{a.faculty ? ` · Faculty of ${a.faculty}` : ""}</div>
              <div className="mt-2"><Pil kind={att[1]}>{att[0]}</Pil> {postponed ? <Pil kind="bad">{slip.batchState === "POSTPONED" ? "Postponed" : "Cancelled"}</Pil> : null}</div>
            </div>
            {qr ? (
              /* eslint-disable-next-line @next/next/no-img-element */
              <img src={qr} alt="Verification QR" width={104} height={104} style={{ flexShrink: 0, border: "1px solid var(--line)", borderRadius: "var(--r-sm)" }} />
            ) : null}
          </div>
          <div className="hr" />
          <KvGrid cls="grid--3" pairs={[
            ["Batch", <strong key="b">{slip.batch}</strong>], ["Date", onDay(slip.heldOn)],
            ["Report by", <strong className="tnum" key="r">{reportingTime(slip)}</strong>],
            ["Examination", `${clock(slip.startsAt)} – ${clock(slip.endsAt)}`],
            ["Centre", slip.centre ? `${slip.centre}${slip.centreLocation ? ` · ${slip.centreLocation}` : ""}` : slip.venue],
            ["Room", slip.room ?? "—"],
            ["Seat", <span className="tnum" key="s">{slip.seat}</span>],
            ["Workstation", slip.workstation ? <span className="tnum" key="w">{slip.workstation}</span> : "Assigned at the seat"],
            ["Bring", "This slip and photo identification"],
          ]} />
          {slip.centreAddress ? <div className="sub2 mt-2">{slip.centreAddress}</div> : null}
          {slip.venueInstructions ? <div className="sub2 mt-1">{slip.venueInstructions}</div> : null}
          {slip.contact ? <div className="sub2 mt-1">Enquiries: {slip.contact}</div> : null}
        </PBody>
      </Panel>
      {slip.instructions ? (
        <Panel title="Examination instructions">
          <PBody><div style={{ whiteSpace: "pre-wrap" }}>{slip.instructions}</div></PBody>
        </Panel>
      ) : null}
      <Panel title="What to bring, and what you may not">
        <DTable cols={["Bring", "Do not bring"]} rows={[
          ["This slip, printed or on your phone", "Any phone, watch or electronic device into the hall"],
          ["Your JAMB result slip", "Written material of any kind"],
          ["A valid photo identification document", "Bags — there is no storage at the venue"],
          ["A dark pen", "Anyone who is not sitting the examination"],
        ]} />
      </Panel>
    </>
  );
}
