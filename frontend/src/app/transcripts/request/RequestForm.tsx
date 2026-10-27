"use client";
/**
 * V668: the public transcript request. Who is asking first: the graduate (proved by a code to the contact on record), the graduate
 * without that contact (an identity document the Transcript Desk checks), or an institution (the graduate consents at their own link).
 * Then where the transcript goes and how; then the reference, the fee and the private link to follow it and pay.
 */
import { useState, type ReactNode } from "react";
import Link from "next/link";
import { Btn, Note } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DELIVERIES, RECIPIENTS, naira, trnCall, type TrnMade, type TrnOptions } from "@/lib/transcripts-public";

type Who = "graduate" | "document" | "institution";
interface Order {
  destination: string; destinationName: string; department: string; recipient: string; recipientEmail: string; address: string; recipientReference: string;
  purpose: string; delivery: string; express: boolean; international: boolean; copies: number;
}
const NO_ORDER: Order = { destination: "SELF", destinationName: "", department: "", recipient: "", recipientEmail: "", address: "", recipientReference: "", purpose: "",
  delivery: "DIGITAL", express: false, international: false, copies: 1 };
const ID_TYPES = ["pdf", "jpg", "jpeg", "png"];

function readDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => { const r = new FileReader(); r.onload = () => resolve(String(r.result)); r.onerror = () => reject(r.error); r.readAsDataURL(file); });
}
const blank = (s: string) => (s.trim() ? s.trim() : null);

/** where the transcript goes and how: the same on every kind of request */
function OrderFields({ o, set, forInstitution }: { o: Order; set: (p: Partial<Order>) => void; forInstitution: boolean }) {
  const toSomeone = forInstitution || o.destination !== "SELF";
  const posted = o.delivery !== "DIGITAL";
  return (
    <>
      <h3 className="trn-h2">Where the transcript goes</h3>
      {!forInstitution ? (
        <Field id="t-dest" label="Send it to">
          <select id="t-dest" className="ctl" value={o.destination} onChange={(e) => set({ destination: e.target.value })}>
            <option value="SELF">Me</option>
            {RECIPIENTS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
        </Field>
      ) : (
        <Field id="t-dest" label="Your organisation is">
          <select id="t-dest" className="ctl" value={o.destination} onChange={(e) => set({ destination: e.target.value })}>
            {RECIPIENTS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
        </Field>
      )}
      {toSomeone ? (
        <div className="trn-row">
          {!forInstitution ? <Field id="t-dn" label="Organisation's name" required><input id="t-dn" className="ctl" maxLength={200} value={o.destinationName} onChange={(e) => set({ destinationName: e.target.value })} /></Field> : null}
          <Field id="t-dep" label="Department or office"><input id="t-dep" className="ctl" maxLength={200} value={o.department} onChange={(e) => set({ department: e.target.value })} placeholder="e.g. Admissions Office" /></Field>
          <Field id="t-rec" label="Addressed to"><input id="t-rec" className="ctl" maxLength={200} value={o.recipient} onChange={(e) => set({ recipient: e.target.value })} placeholder="e.g. The Registrar" /></Field>
          <Field id="t-re" label="Email it goes to" required={o.delivery !== "PHYSICAL"} hint="The secure link is sent here"><input id="t-re" type="email" className="ctl" maxLength={200} value={o.recipientEmail} onChange={(e) => set({ recipientEmail: e.target.value })} /></Field>
          <Field id="t-rr" label="Their reference, if any"><input id="t-rr" className="ctl" maxLength={100} value={o.recipientReference} onChange={(e) => set({ recipientReference: e.target.value })} /></Field>
        </div>
      ) : null}
      <Field id="t-pur" label="Purpose" hint="Written into the covering letter, e.g. postgraduate admission, employment"><input id="t-pur" className="ctl" maxLength={200} value={o.purpose} onChange={(e) => set({ purpose: e.target.value })} /></Field>
      <div className="trn-row">
        <Field id="t-del" label="How">
          <select id="t-del" className="ctl" value={o.delivery} onChange={(e) => set({ delivery: e.target.value })}>{DELIVERIES.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
        </Field>
        {posted ? <Field id="t-cp" label="Printed copies"><input id="t-cp" type="number" min={1} max={10} className="ctl" value={o.copies} onChange={(e) => set({ copies: Math.max(1, Math.min(10, Number(e.target.value) || 1)) })} /></Field> : null}
      </div>
      {posted ? (
        <>
          <Field id="t-addr" label="Postal address" required full><textarea id="t-addr" className="ctl" rows={3} maxLength={1000} value={o.address} onChange={(e) => set({ address: e.target.value })} /></Field>
          <label className="row row--tight"><input type="checkbox" checked={o.international} onChange={(e) => set({ international: e.target.checked })} /> The address is outside Nigeria</label>
        </>
      ) : null}
      <label className="row row--tight"><input type="checkbox" checked={o.express} onChange={(e) => set({ express: e.target.checked })} /> Urgent (a higher fee, a shorter wait)</label>
    </>
  );
}

function payload(o: Order, forInstitution: boolean, organisation?: string) {
  const toSomeone = forInstitution || o.destination !== "SELF";
  return {
    kind: "TRANSCRIPT", destination: o.destination, destinationName: forInstitution ? (organisation ?? null) : toSomeone ? blank(o.destinationName) : null,
    department: toSomeone ? blank(o.department) : null, recipient: toSomeone ? blank(o.recipient) : null, recipientEmail: toSomeone ? blank(o.recipientEmail) : null,
    address: o.delivery !== "DIGITAL" ? blank(o.address) : null, recipientReference: toSomeone ? blank(o.recipientReference) : null, purpose: blank(o.purpose),
    delivery: o.delivery, express: o.express, international: o.delivery !== "DIGITAL" && o.international, copies: o.delivery !== "DIGITAL" ? o.copies : 1,
  };
}

export function RequestForm({ options }: { options: TrnOptions }) {
  const [who, setWho] = useState<Who | null>(null);
  const [matric, setMatric] = useState("");
  const [dob, setDob] = useState("");
  const [surname, setSurname] = useState("");
  const [sent, setSent] = useState<{ challenge: string; email: string | null; phone: string | null } | null>(null);
  const [code, setCode] = useState("");
  const [pass, setPass] = useState<{ pass: string; graduate: { name: string; matric_no: string; programme: string } } | null>(null);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [organisation, setOrganisation] = useState("");
  const [idFile, setIdFile] = useState<File | null>(null);
  const [o, setO] = useState<Order>(NO_ORDER);
  const [hp, setHp] = useState("");
  const [message, setMessage] = useState<{ kind: "bad" | "info"; text: ReactNode } | null>(null);
  const [done, setDone] = useState<TrnMade | null>(null);
  const set = (p: Partial<Order>) => setO((x) => ({ ...x, ...p }));

  function choose(w: Who) {
    setWho(w); setMessage(null); setSent(null); setPass(null); setCode("");
    setO(w === "institution" ? { ...NO_ORDER, destination: "INSTITUTION" } : NO_ORDER);
  }

  /** what the form can tell before the server does */
  function orderProblem(forInstitution: boolean): string | null {
    const toSomeone = forInstitution || o.destination !== "SELF";
    if (!forInstitution && toSomeone && !o.destinationName.trim()) return "Give the organisation's name.";
    if (toSomeone && o.delivery !== "PHYSICAL" && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(o.recipientEmail.trim())) return "Give the email the transcript goes to.";
    if (o.delivery !== "DIGITAL" && o.address.trim().length < 8) return "Give the postal address for the printed copy.";
    return null;
  }

  async function sendCode() {
    if (!matric.trim() || !dob) { setMessage({ kind: "bad", text: "Give your matriculation number and your date of birth." }); return; }
    setMessage(null);
    const r = await trnCall<{ challenge: string; email: string | null; phone: string | null }>("POST", "/code", { matricNo: matric.trim(), dateOfBirth: dob, website2: hp });
    if (!r.ok) {
      if (r.code === "TRN_NO_CONTACT") {
        setMessage({ kind: "info", text: <>There is no email or phone on your record to send a code to. <button type="button" className="lnk" onClick={() => choose("document")}>Request with an identity document instead</button>.</> });
      } else setMessage({ kind: "bad", text: r.message });
      return;
    }
    setSent(r.data);
  }

  async function checkCode() {
    if (!sent) return;
    if (!/^\d{6}$/.test(code.trim())) { setMessage({ kind: "bad", text: "Type the six digits of the code." }); return; }
    setMessage(null);
    const r = await trnCall<{ pass: string; graduate: { name: string; matric_no: string; programme: string } }>("POST", "/code/check", { challenge: sent.challenge, code: code.trim() });
    if (!r.ok) { setMessage({ kind: "bad", text: r.message }); return; }
    setPass(r.data);
  }

  async function submit() {
    const forInstitution = who === "institution";
    const bad = orderProblem(forInstitution);
    if (bad) { setMessage({ kind: "bad", text: bad }); return; }
    setMessage(null);
    let r: Awaited<ReturnType<typeof trnCall<TrnMade>>>;
    if (who === "graduate" && pass) {
      r = await trnCall<TrnMade>("POST", "/requests/graduate", { pass: pass.pass, name: blank(name), email: blank(email), phone: blank(phone), order: payload(o, false), website2: hp });
    } else if (who === "document") {
      if (!matric.trim() || !dob || !name.trim() || !email.trim()) { setMessage({ kind: "bad", text: "Give your matriculation number, date of birth, full name and email." }); return; }
      if (!idFile) { setMessage({ kind: "bad", text: "Attach a photograph or scan of your identity document." }); return; }
      const ext = idFile.name.split(".").pop()?.toLowerCase() ?? "";
      if (!ID_TYPES.includes(ext) || idFile.size > options.maxIdMb * 1024 * 1024) { setMessage({ kind: "bad", text: `The identity document must be a PDF, JPEG or PNG of at most ${options.maxIdMb} MB.` }); return; }
      r = await trnCall<TrnMade>("POST", "/requests/with-document", { matricNo: matric.trim(), dateOfBirth: dob, name: name.trim(), email: email.trim(), phone: blank(phone),
        idFilename: idFile.name, idDataUrl: await readDataUrl(idFile), order: payload(o, false), website2: hp });
    } else {
      if (!matric.trim() || !surname.trim() || !organisation.trim() || !name.trim() || !email.trim()) { setMessage({ kind: "bad", text: "Give the graduate's matriculation number and surname, your organisation, your name and your email." }); return; }
      r = await trnCall<TrnMade>("POST", "/requests/institution", { matricNo: matric.trim(), surname: surname.trim(), organisation: organisation.trim(), name: name.trim(),
        email: email.trim(), phone: blank(phone), order: payload(o, true, organisation.trim()), website2: hp });
    }
    if (!r.ok) { setMessage({ kind: "bad", text: r.message }); return; }
    setDone(r.data);
  }

  if (done) {
    return (
      <div className="trn-form" aria-live="polite">
        <Note kind="ok" title={`Request ${done.ref} received`}>
          {done.fee ? <>The fee is {naira(done.fee)}. Pay it with the payment reference <strong className="tnum">{done.reference}</strong>, online from your request&rsquo;s page or at any bank. </> : null}
          {who === "institution" ? "We have asked the graduate to consent; nothing is prepared until they do. " : who === "document" ? "The Transcript Desk will check your identity document; you are told by email when it has. " : ""}
          A private link to follow the request has been emailed to you.
        </Note>
        <div className="row row--tight"><Link className="btn btn--primary btn--md" href={done.statusPath}>Follow the request and pay</Link></div>
      </div>
    );
  }

  const hpField = <div className="trn-hp" aria-hidden="true"><label htmlFor="t-website2">Leave this empty</label><input id="t-website2" tabIndex={-1} autoComplete="off" value={hp} onChange={(e) => setHp(e.target.value)} /></div>;
  const note = message ? <Note kind={message.kind} title={message.text} /> : null;

  return (
    <div className="trn-form">
      <h2 className="trn-h2" style={{ marginTop: 0 }}>Who is asking?</h2>
      <div className="trn-who" role="group" aria-label="Who is asking">
        <button type="button" aria-pressed={who === "graduate"} onClick={() => choose("graduate")}><strong>I am the graduate</strong>We send a code to the email or phone on your record.</button>
        <button type="button" aria-pressed={who === "document"} onClick={() => choose("document")}><strong>I am the graduate, without that email or phone</strong>Attach an identity document; the Transcript Desk checks it.</button>
        <button type="button" aria-pressed={who === "institution"} onClick={() => choose("institution")}><strong>I am an institution or employer</strong>The graduate is asked to consent before anything is prepared.</button>
      </div>
      {hpField}

      {who === "graduate" ? (
        !pass ? (
          <>
            <div className="trn-row">
              <Field id="t-m" label="Matriculation number" required><input id="t-m" className="ctl" maxLength={40} autoComplete="off" value={matric} onChange={(e) => setMatric(e.target.value)} disabled={!!sent} placeholder="e.g. BSU/MS/ACC/17/7929" /></Field>
              <Field id="t-dob" label="Date of birth" required><input id="t-dob" type="date" className="ctl" value={dob} onChange={(e) => setDob(e.target.value)} disabled={!!sent} /></Field>
            </div>
            {!sent ? <div className="row row--tight"><Btn kind="primary" size="md" onClick={sendCode}>Send me a code</Btn></div> : (
              <>
                <Note kind="info" title={`We sent a six-digit code to ${[sent.email, sent.phone].filter(Boolean).join(" and ")}.`}>It works for 15 minutes. Not yours any more? <button type="button" className="lnk" onClick={() => choose("document")}>Request with an identity document</button>.</Note>
                <Field id="t-code" label="The code" required><input id="t-code" className="ctl trn-code" inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))} /></Field>
                <div className="row row--tight"><Btn kind="primary" size="md" onClick={checkCode}>Confirm</Btn><Btn kind="ghost" onClick={() => { setSent(null); setCode(""); }}>Send a new code</Btn></div>
              </>
            )}
            {note}
          </>
        ) : (
          <>
            <Note kind="ok" title={`Confirmed: ${pass.graduate.name}, ${pass.graduate.matric_no}`}>{pass.graduate.programme}. Finish within the hour.</Note>
            <div className="trn-row">
              <Field id="t-e" label="Your email for this request" hint="Leave empty to use the one on your record"><input id="t-e" type="email" className="ctl" maxLength={200} value={email} onChange={(e) => setEmail(e.target.value)} /></Field>
              <Field id="t-p" label="Your phone" hint="Leave empty to use the one on your record"><input id="t-p" type="tel" className="ctl" maxLength={40} value={phone} onChange={(e) => setPhone(e.target.value)} /></Field>
            </div>
            <OrderFields o={o} set={set} forInstitution={false} />
            {note}
            <div className="row row--tight"><Btn kind="primary" size="md" onClick={submit}>Submit the request</Btn></div>
          </>
        )
      ) : null}

      {who === "document" ? (
        <>
          <div className="trn-row">
            <Field id="t-m" label="Matriculation number" required><input id="t-m" className="ctl" maxLength={40} autoComplete="off" value={matric} onChange={(e) => setMatric(e.target.value)} /></Field>
            <Field id="t-dob" label="Date of birth" required><input id="t-dob" type="date" className="ctl" value={dob} onChange={(e) => setDob(e.target.value)} /></Field>
            <Field id="t-n" label="Full name" required><input id="t-n" className="ctl" maxLength={200} autoComplete="name" value={name} onChange={(e) => setName(e.target.value)} /></Field>
            <Field id="t-e" label="Email" required hint="We write to you here"><input id="t-e" type="email" className="ctl" maxLength={200} autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} /></Field>
            <Field id="t-p" label="Phone"><input id="t-p" type="tel" className="ctl" maxLength={40} autoComplete="tel" value={phone} onChange={(e) => setPhone(e.target.value)} /></Field>
          </div>
          <Field id="t-id" label="Identity document" required full hint={`A passport, national ID card, driver's licence or voter's card: a PDF, JPEG or PNG of at most ${options.maxIdMb} MB`}>
            <input id="t-id" type="file" className="ctl" accept=".pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png" onChange={(e) => setIdFile(e.target.files?.[0] ?? null)} />
          </Field>
          <OrderFields o={o} set={set} forInstitution={false} />
          {note}
          <div className="row row--tight"><Btn kind="primary" size="md" onClick={submit}>Submit the request</Btn></div>
        </>
      ) : null}

      {who === "institution" ? (
        <>
          <h3 className="trn-h2">The graduate</h3>
          <div className="trn-row">
            <Field id="t-m" label="Matriculation number" required><input id="t-m" className="ctl" maxLength={40} autoComplete="off" value={matric} onChange={(e) => setMatric(e.target.value)} /></Field>
            <Field id="t-sn" label="Surname" required><input id="t-sn" className="ctl" maxLength={100} autoComplete="off" value={surname} onChange={(e) => setSurname(e.target.value)} /></Field>
          </div>
          <h3 className="trn-h2">You</h3>
          <div className="trn-row">
            <Field id="t-org" label="Organisation" required><input id="t-org" className="ctl" maxLength={200} autoComplete="organization" value={organisation} onChange={(e) => setOrganisation(e.target.value)} /></Field>
            <Field id="t-n" label="Your name" required><input id="t-n" className="ctl" maxLength={200} autoComplete="name" value={name} onChange={(e) => setName(e.target.value)} /></Field>
            <Field id="t-e" label="Your email" required><input id="t-e" type="email" className="ctl" maxLength={200} autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} /></Field>
            <Field id="t-p" label="Your phone"><input id="t-p" type="tel" className="ctl" maxLength={40} autoComplete="tel" value={phone} onChange={(e) => setPhone(e.target.value)} /></Field>
          </div>
          <OrderFields o={o} set={set} forInstitution />
          {note}
          <div className="row row--tight"><Btn kind="primary" size="md" onClick={submit}>Submit the request</Btn></div>
        </>
      ) : null}
    </div>
  );
}
