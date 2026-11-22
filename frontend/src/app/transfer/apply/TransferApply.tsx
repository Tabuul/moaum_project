"use client";

/** V766: the public inter-university transfer application — the link a student of another university opens to apply on their own. The
 *  form asks who they are, their present university and standing there, the programme and level applied for (only those the Academic
 *  Office opened for the session), why, and a password; registering signs them in at once on their application (IUT/APP/…), where they
 *  pay the published fee (or none), upload the documents asked and submit. Nothing here decides: the database checks every rule again. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PasswordInput } from "@/components/PasswordInput";
import { AuthLayout } from "@/components/auth/AuthLayout";
import {
  MAX_DOCUMENT_BYTES, applyBody, applyErrors, documentsWords, emptyApplyForm, naira, num, sizeWords,
  type ApplyField, type ApplyForm, type PublicOptions,
} from "@/lib/transfer-application";
import { ApplyFields, Section } from "../ApplyFields";

export function TransferApply({ options }: { options: PublicOptions }) {
  const router = useRouter();
  const [f, setF] = useState<ApplyForm>(emptyApplyForm());
  const [tried, setTried] = useState(false);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const session = options.session ?? options.window?.session ?? null;
  const programmes = options.programmes ?? [];
  const universities = options.universities ?? [];
  const errors = applyErrors(f, { programmes, universities, session });
  const set = (patch: Partial<ApplyForm>) => setF((x) => ({ ...x, ...patch }));
  const docs = documentsWords(options.documents);
  const fee = options.fee?.amount;
  const max = options.maxDocumentBytes ?? MAX_DOCUMENT_BYTES;

  async function submit() {
    setTried(true);
    setProblem(null);
    const first = Object.keys(errors)[0] as ApplyField | undefined;
    if (first) {
      notifyProblem({ status: 400, title: "The form is not complete", detail: errors[first] ?? "" });
      document.getElementById(`ta-${first}`)?.focus();
      return;
    }
    setBusy(true);
    try {
      const r = await fetch("/api/auth/transfer/register", {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...applyBody(f), acceptPolicy: f.privacy }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        const p: Problem = j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText || "The application did not go through" };
        setProblem(p);
        notifyProblem(p);
        return;
      }
      notify(`${(j as { applicationNo?: string }).applicationNo ?? "Your application"}: started. Pay the fee, upload your documents, then submit.`);
      router.push("/transfer/portal");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <AuthLayout eyebrow={<>Inter-university transfer{session ? ` ${session}` : ""}</>} wide
      lead={<>For a student of another university who wishes to continue their studies here. Apply on your own: the University checks your documents, the Head of Department of the programme assesses your standing, and the Registry decides.</>}
      stats={[[programmes.length, programmes.length === 1 ? "programme open" : "programmes open"], [fee != null && num(fee) > 0 ? naira(fee) : "₦0", "application fee"], ["5 MB", "a document, at most"]]}>
      <div style={{ width: "100%", maxWidth: 680, display: "grid", gap: "var(--s-4)" }}>
        <Note kind="info" title={`Apply for an inter-university transfer${session ? ` · ${session}` : ""}`}>
          One live application a JAMB registration number. You need an e-mail address and a Nigerian phone number, the JAMB registration number of your present
          admission, and your documents to upload after you register. Already applied? <Link className="lnk" href="/login">Sign in</Link> with your e-mail or application number.
        </Note>
        {problem ? <ProblemNotice problem={problem} /> : null}
        <form className="card" noValidate onSubmit={(e) => { e.preventDefault(); void submit(); }}>
          <div className="card__body">
            <ApplyFields f={f} set={set} programmes={programmes} universities={universities} session={session} errors={errors} shown={tried} />

            <Section title="Your password" />
            <div className="grid grid--2">
              <Field id="ta-password" label="Password" required error={tried ? errors.password : undefined} hint="At least 8 characters; not your JAMB number">
                <PasswordInput id="ta-password" className="ctl" value={f.password} onChange={(e) => set({ password: e.target.value })} autoComplete="new-password" />
              </Field>
              <Field id="ta-password2" label="Confirm password" required error={tried ? errors.password2 : undefined}>
                <PasswordInput id="ta-password2" className="ctl" value={f.password2} onChange={(e) => set({ password2: e.target.value })} autoComplete="new-password" />
              </Field>
            </div>

            <Section title="The fee and documents" />
            <div className="sub2 mt-1">
              {fee != null && num(fee) > 0
                ? <>The application fee for {session ?? "the session"} is <b>{naira(fee)}</b>, paid online after you register.</>
                : <>No application fee is charged for {session ?? "the session"}.</>}
              {docs.required ? <> You then upload: {docs.required}{docs.optional ? <>; optional: {docs.optional}</> : null}.</> : null}
              {" "}PDF, JPEG or PNG, at most {sizeWords(max)} each.
            </div>

            {/* a form filled by a program fills this too; a person never sees it */}
            <div aria-hidden="true" style={{ position: "absolute", left: -10000, top: "auto", width: 1, height: 1, overflow: "hidden" }}>
              <label htmlFor="ta-website2">Leave this empty</label>
              <input id="ta-website2" tabIndex={-1} autoComplete="off" value={f.website2} onChange={(e) => set({ website2: e.target.value })} />
            </div>

            <label className="row row--inline row--tight mt-2" htmlFor="ta-privacy">
              <input id="ta-privacy" type="checkbox" checked={f.privacy} onChange={(e) => set({ privacy: e.target.checked })} /> I have read the{" "}
              <a className="lnk" href="/privacy-policy" target="_blank" rel="noopener">Privacy Policy</a> and accept how the University handles my information.
            </label>
            {tried && errors.privacy ? <div className="ferr" role="alert">{errors.privacy}</div> : null}
            <div className="row mt-2">
              <LinkBtn kind="ghost" href="/login">Cancel</LinkBtn>
              <span className="grow" />
              <Btn kind="primary" size="md" type="submit" busy={busy} busyLabel="Registering…">Register and continue</Btn>
            </div>
          </div>
        </form>
        <div className="hint" style={{ textAlign: "center" }}>Already applied? <Link href="/login">Sign in</Link> · <Link href="/login/forgot">Forgot your password?</Link></div>
      </div>
    </AuthLayout>
  );
}
