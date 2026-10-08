"use client";

/**
 * The public JUPEB application (V339): the few things the University needs to open an application — who the candidate is
 * (names, sex, date of birth, NIN), how to reach them (email, phone), the programme — Science or Non-Science (V341, V342) — and a password. The subject combination is chosen after signing in.
 * The candidate then signs in, pays the application fee (the amount is the Bursary's, stated by the server) and continues the
 * biodata, O'Level and documents on their dashboard before submitting. The subject combination is chosen at subject
 * registration, once the school fee has activated the student.
 */
import { useEffect, useState, type ChangeEvent, type ReactNode } from "react";
import Link from "next/link";
import type { Problem } from "@/lib/api";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { jcall, naira } from "@/lib/jupeb";
import { AuthLayout } from "@/components/auth/AuthLayout";

interface Options { session: string; applicationFee: number; streams: { code: string; label: string }[]; documents: { code: string; label: string; required: boolean }[] }
interface Applied { application_no: string; reference: string; amount: number }

export function JupebApply() {
  const [opts, setOpts] = useState<Options | null>(null);
  const [f, setF] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [applied, setApplied] = useState<Applied | null>(null);

  useEffect(() => {
    let live = true;
    void jcall<Options>("/api/v1/jupeb/options").then((r) => { if (live && r.ok) setOpts(r.data); });
    return () => { live = false; };
  }, []);

  const set = (k: string) => (e: ChangeEvent<HTMLInputElement | HTMLSelectElement>) => setF({ ...f, [k]: e.target.value });

  function fail(title: string) {
    const p: Problem = { status: 400, title };
    setProblem(p); notifyProblem(p);
  }

  async function submit() {
    setProblem(null);
    if (!f.surname?.trim() || !f.firstName?.trim()) return fail("Your surname and first name are required.");
    if (!f.sex || !f.dob) return fail("Your sex and date of birth are required.");
    if (!/^[0-9]{11}$/.test(f.nin ?? "")) return fail("Your NIN is the eleven digits on your NIN slip.");
    if (!f.email?.trim()) return fail("Your email is required — you sign in with it.");
    if (!/^0[0-9]{10}$/.test(f.phone ?? "")) return fail("Your phone is an eleven-digit number, e.g. 08012345678.");
    if (!f.stream) return fail("Choose your programme: Science or Non-Science.");
    if ((f.password ?? "").length < 8) return fail("Choose a password of at least eight characters.");
    if (f.password !== f.password2) return fail("The two passwords do not match.");
    setBusy(true);
    try {
      const body = {
        surname: f.surname.trim(), firstName: f.firstName.trim(), middleName: f.middleName?.trim() || null, sex: f.sex, dob: f.dob, nin: f.nin,
        email: f.email.trim(), phone: f.phone, password: f.password, stream: f.stream,
      };
      const r = await jcall<Applied>("/api/v1/jupeb/apply", "POST", body);
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      setApplied(r.data);
    } finally { setBusy(false); }
  }

  if (applied) {
    return (
      <Wrap>
        <Note kind="ok" title={`Application started — ${applied.application_no}`}>
          Keep your application number: it is yours for good. <b>Sign in to pay the application fee of {naira(applied.amount)}</b>, then continue on your
          dashboard — your other biodata, your O&rsquo;Level results and your documents — and submit.
        </Note>
        <div className="card"><div className="card__body">
          <Row k="Application number" v={applied.application_no} />
          <Row k="Payment reference" v={applied.reference} />
          <Row k="Application fee" v={naira(applied.amount)} />
        </div></div>
        <div className="row" style={{ justifyContent: "center" }}><LinkBtn kind="primary" size="md" href="/login?next=/jupeb/portal">Sign in to pay and continue</LinkBtn></div>
        <div style={{ textAlign: "center" }}><Link href="/login">Back to sign in</Link></div>
      </Wrap>
    );
  }

  return (
    <Wrap>
      <Note kind="info" title={`Apply for JUPEB${opts ? ` · ${opts.session}` : ""}`}>
        Start your application here. You need an email address and phone you can reach, your NIN, and at least five O&rsquo;Level credits including
        English Language and Mathematics, in no more than two sittings. The application fee is {opts ? naira(opts.applicationFee) : "stated after you submit"}.
        After signing in you complete the rest on your dashboard.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <div className="card"><div className="card__body">
        <Section title="About you" />
        <div className="grid grid--2">
          <Field id="surname" label="Surname" required><input id="surname" className="ctl" value={f.surname ?? ""} onChange={set("surname")} autoComplete="family-name" maxLength={80} /></Field>
          <Field id="firstName" label="First name" required><input id="firstName" className="ctl" value={f.firstName ?? ""} onChange={set("firstName")} autoComplete="given-name" maxLength={80} /></Field>
          <Field id="middleName" label="Middle name"><input id="middleName" className="ctl" value={f.middleName ?? ""} onChange={set("middleName")} autoComplete="additional-name" maxLength={80} /></Field>
          <Field id="sex" label="Sex" required><select id="sex" className="ctl" value={f.sex ?? ""} onChange={set("sex")}><option value="">—</option><option value="F">Female</option><option value="M">Male</option></select></Field>
          <Field id="dob" label="Date of birth" required><input id="dob" type="date" className="ctl" value={f.dob ?? ""} onChange={set("dob")} /></Field>
          <Field id="nin" label="NIN" required hint="The eleven digits on your NIN slip"><input id="nin" className="ctl tnum" inputMode="numeric" maxLength={11} value={f.nin ?? ""} onChange={(e) => setF({ ...f, nin: e.target.value.replace(/\D/g, "") })} /></Field>
          <Field id="email" label="Email" required hint="You sign in with it; your notices come here"><input id="email" type="email" className="ctl" value={f.email ?? ""} onChange={set("email")} autoComplete="email" maxLength={160} /></Field>
          <Field id="phone" label="Phone" required><input id="phone" className="ctl tnum" inputMode="tel" maxLength={11} placeholder="08012345678" value={f.phone ?? ""} onChange={(e) => setF({ ...f, phone: e.target.value.replace(/\D/g, "") })} autoComplete="tel" /></Field>
        </div>

        <Section title="Your programme" />
        <Field id="stream" label="Programme" required>
          <select id="stream" className="ctl" value={f.stream ?? ""} onChange={set("stream")}>
            <option value="">— Science or Non-Science —</option>
            {(opts?.streams ?? [{ code: "SCIENCE", label: "Science" }, { code: "NON_SCIENCE", label: "Non-Science" }]).map((x) => <option key={x.code} value={x.code}>{x.label}</option>)}
          </select>
        </Field>

        <Section title="Your password" />
        <div className="grid grid--2">
          <Field id="password" label="Password" required hint="At least eight characters"><input id="password" type="password" className="ctl" value={f.password ?? ""} onChange={set("password")} autoComplete="new-password" /></Field>
          <Field id="password2" label="Confirm password" required><input id="password2" type="password" className="ctl" value={f.password2 ?? ""} onChange={set("password2")} autoComplete="new-password" /></Field>
        </div>

        <div className="row mt-1">
          <LinkBtn kind="ghost" href="/login">Cancel</LinkBtn>
          <span className="grow" />
          <Btn kind="primary" size="md" disabled={busy || !opts} onClick={() => void submit()}>{busy ? "Starting…" : "Start my application"}</Btn>
        </div>
      </div></div>
      <div className="hint" style={{ textAlign: "center" }}>Already applied? <Link href="/login?next=/jupeb/portal">Sign in</Link> with your email or JUPEB application number · <Link href="/jupeb/reset">Forgot your password?</Link></div>
    </Wrap>
  );
}

function Wrap({ children }: { children: ReactNode }) {
  return (
    <AuthLayout eyebrow="JUPEB programme" lead={<>Apply for the Joint Universities Preliminary Examinations Board programme: one year of three subjects, examined by the Board, leading to direct entry into 200 level. No JAMB number is needed to apply.</>} stats={[["3", "subjects"], ["5", <>O&rsquo;Level credits</>], ["0", "JAMB number needed"]]} wide>
        <div style={{ width: "100%", maxWidth: 640, display: "grid", gap: "var(--s-4)" }}>{children}</div>
    </AuthLayout>
  );
}

function Section({ title }: { title: string }) {
  return <div className="eyebrow" style={{ borderBottom: "1px solid var(--line-2)", paddingBottom: "var(--s-1)", marginTop: "var(--s-2)" }}>{title}</div>;
}
function Row({ k, v }: { k: string; v: string }) {
  return <div className="row row--between" style={{ padding: "var(--s-2) 0", borderBottom: "1px solid var(--line-2)" }}><span className="sub2">{k}</span><span className="tnum b700">{v}</span></div>;
}
