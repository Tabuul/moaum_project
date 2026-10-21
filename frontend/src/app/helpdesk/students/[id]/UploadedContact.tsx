"use client";

/** V575: on the desk's Reach panel, a phone or e-mail a department uploaded that the student has not confirmed. No reset link goes
 *  to it until it is confirmed; an agent with contact editing confirms it after checking it with the student, saying how.
 *  V599: and one the sign-in help saved from a request on the sign-in page (V596), which reaches no notice either until it is
 *  confirmed; either kind is refused when it is not the student's (the field emptied, an uploading department told). */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { fieldWord } from "@/lib/sign-in-contacts";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Pil } from "@/components/proto/ui";

export function UploadedContact({ id, field, may, ticket, source = "UPLOAD", request = null }: {
  id: string; field: "EMAIL" | "PHONE"; may: boolean; ticket: string | null; source?: "UPLOAD" | "SIGN_IN"; request?: string | null;
}) {
  const router = useRouter();
  const [open, setOpen] = useState<"confirm" | "refuse" | null>(null);
  const [why, setWhy] = useState("");
  const [busy, setBusy] = useState(false);
  const word = fieldWord(field);
  const from = source === "SIGN_IN" ? "saved from the sign-in page" : "uploaded";

  async function decide(kind: "confirm" | "refuse") {
    setBusy(true);
    try {
      const said = kind === "confirm" ? `The ${word} ${from} confirmed with the student: ${why.trim()}` : `The ${word} ${from} refused, not the student's: ${why.trim()}`;
      const r = await fetch(`/api/bff/api/v1/helpdesk/support/students/${encodeURIComponent(id)}/contact/${kind}`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(said) },
        body: JSON.stringify({ field, reason: why.trim(), ticket }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(kind === "confirm"
        ? `The ${word} is confirmed: ${source === "SIGN_IN" ? "notices and reset links" : "reset links"} may go to it`
        : `The ${word} is removed from the record`);
      setOpen(null);
      setWhy("");
      router.refresh();
    } finally { setBusy(false); }
  }

  return (
    <div className="stack" style={{ gap: 4, alignItems: "flex-end" }}>
      <Pil kind="warn" title={source === "SIGN_IN" ? "No notice and no reset link goes to it until it is confirmed" : "No reset link goes to it until it is confirmed"}>
        {source === "SIGN_IN" ? `From the sign-in page${request ? ` (${request})` : ""} — not confirmed` : "From an upload — not confirmed"}
      </Pil>
      {may && !open ? (
        <div className="row row--tight" style={{ gap: 6 }}>
          <Btn kind="ghost" size="sm" onClick={() => setOpen("confirm")}>Confirmed with the student</Btn>
          <Btn kind="ghost" size="sm" onClick={() => setOpen("refuse")}>Not the student&apos;s</Btn>
        </div>
      ) : null}
      {may && open ? (
        <form className="row row--tight" style={{ gap: 6, flexWrap: "wrap", justifyContent: "flex-end" }} onSubmit={(e) => { e.preventDefault(); void decide(open); }}>
          <input className="ctl" style={{ minWidth: 220 }} aria-label={open === "confirm" ? `How the ${word} was checked` : `Why the ${word} is not the student's`}
            placeholder={open === "confirm" ? "How it was checked (10 characters or more)" : "Why it is not theirs (10 characters or more)"}
            value={why} onChange={(e) => setWhy(e.target.value)} maxLength={2000} />
          <Btn kind={open === "confirm" ? "primary" : "urgent"} size="sm" type="submit" disabled={busy || why.trim().length < 10}>{open === "confirm" ? "Confirm" : "Remove it"}</Btn>
          <Btn kind="ghost" size="sm" disabled={busy} onClick={() => setOpen(null)}>Cancel</Btn>
        </form>
      ) : null}
    </div>
  );
}
