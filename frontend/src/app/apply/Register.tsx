"use client";

/**
 * Post-UTME registration — proto/part13.html applicantRegister, as drawn.
 * The registration number is the first field and, until it is verified
 * against the list the Academic Office loaded, the ONLY field. The name and
 * the programme are read from that list and shown back, never asked for.
 */
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { Note } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";

const REG_SHAPE = /^\d{12}[A-Z]{2,3}$/;
const EMAIL_SHAPE = /^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$/;
const MAIL_TYPO: Record<string, string> = {
  "gmial.com": "gmail.com", "gmai.com": "gmail.com", "gmail.co": "gmail.com", "gnail.com": "gmail.com", "gmail.con": "gmail.com", "gamil.com": "gmail.com",
  "yahooo.com": "yahoo.com", "yaho.com": "yahoo.com", "yahoo.co": "yahoo.com", "hotmial.com": "hotmail.com", "outlok.com": "outlook.com",
};

function mailTypo(v: string): string {
  const at = v.toLowerCase().split("@");
  return at.length === 2 ? MAIL_TYPO[at[1]] ?? "" : "";
}

/** Read a number written any of the three usual ways. */
export function phoneRead(v: string): { digits: string; how: string; ok: boolean } {
  let d = v.replace(/[^0-9]/g, "");
  let how = "";
  if (d.length === 13 && d.startsWith("234")) { d = "0" + d.slice(3); how = "read from the +234 form"; }
  else if (d.length === 10 && d[0] !== "0") { d = "0" + d; how = "the leading zero was added"; }
  return { digits: d, how, ok: d.length === 11 && d[0] === "0" };
}

type Found = { state: "idle" | "nolist" | "none" | "found" | "registered"; name?: string; programme?: string; list?: string };

export function Register({ session }: { session: string }) {
  const router = useRouter();
  const [num, setNum] = useState("");
  const [looked, setLooked] = useState<{ key: string; found: Found } | null>(null);
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [pw, setPw] = useState("");
  const [pw2, setPw2] = useState("");
  const [show, setShow] = useState(false);
  const [err, setErr] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const key = num.trim().toUpperCase();

  /* checked on every keystroke, idle until the number is the right shape */
  const shaped = REG_SHAPE.test(key);
  useEffect(() => {
    if (!shaped) return;
    let live = true;
    (async () => {
      const r = await fetch("/api/bff/api/v1/applicant/lookup", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ session, jambKey: key }) });
      const j = await r.json().catch(() => null);
      if (live) setLooked({ key, found: r.ok && j ? (j as Found) : { state: "idle" } });
    })();
    return () => { live = false; };
  }, [key, shaped, session]);
  const found: Found = shaped && looked && looked.key === key ? looked.found : { state: "idle" };

  function judge(): boolean {
    const e: Record<string, string> = {};
    const mail = email.trim();
    if (!mail) e.email = "An email address is required. This is where the offer is sent.";
    else if (!EMAIL_SHAPE.test(mail)) e.email = "That is not a complete address. It needs a name, an @, and a domain with a dot in it — you@example.com.";
    const ph = phoneRead(phone);
    if (!phone.trim()) e.phone = "A phone number is required. Screening batches and venue changes are sent by SMS.";
    else if (!ph.ok) e.phone = ph.digits.length === 11 ? "Eleven digits, but a Nigerian mobile number begins with a zero. Check the first digit." : `That is ${ph.digits.length} digit${ph.digits.length === 1 ? "" : "s"}. Eleven are needed, beginning with a zero — 0803 411 7725. Written as +234 or without the zero is fine.`;
    if (!pw) e.pw = "Choose a password.";
    else if (pw.length < 8) e.pw = "Eight characters at the very least. This one account carries you to graduation.";
    if (!e.pw && !pw2) e.pw2 = "Type it a second time.";
    else if (!e.pw && pw !== pw2) e.pw2 = "The two do not match. Nothing has been saved and nothing is lost — type both again, or press Show to see them.";
    setErr(e);
    return Object.keys(e).length === 0;
  }

  async function create() {
    if (!judge()) return;
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/auth/applicant/register", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ session, jambKey: key, email: email.trim(), phone: phoneRead(phone).digits, password: pw }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      router.push("/applicant");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  const ph = phoneRead(phone);
  const phoneHint = err.phone ? "" : !phone ? "Eleven digits, beginning with a zero. Written with +234 or without the zero is fine — it is read either way."
    : ph.how && ph.ok ? `Read as ${ph.digits} — ${ph.how}.` : ph.ok ? "Eleven digits. Screening batches are sent here by SMS." : `${ph.digits.length} of 11 digits so far.`;

  const field = (id: string, label: string, k: string, input: React.ReactNode, hint: React.ReactNode) => (
    <div className="field">
      <label htmlFor={id}>{label}<span className="lreq">required</span></label>
      {input}
      {err[k] ? <div className="ferr">{err[k]}</div> : null}
      {hint ? <div className="hint">{hint}</div> : null}
    </div>
  );

  return (
    <div className="login-wrap">
      <div className="login-brand">
        <div>
          <div className="login-brand__top">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/crest.png" alt="University crest" style={{ width: 56, height: 58, objectFit: "contain" }} />
            <div><span style={{ fontSize: 12, letterSpacing: ".6px", textTransform: "uppercase", color: "var(--chrome-dim)" }}>Admissions {session}</span></div>
          </div>
          <div style={{ height: 26 }} />
          <h1>Create your application account</h1>
          <p>One account carries you from application through screening and admission, and becomes your student account on the day you matriculate.</p>
        </div>
        <div className="login-stats">
          <div className="login-stat"><span className="n tnum">{session.slice(0, 4)}</span><span className="l">admission year</span></div>
          <div className="login-stat"><span className="n tnum">1</span><span className="l">account, to graduation</span></div>
          <div className="login-stat"><span className="n tnum">0</span><span className="l">fees paid anywhere but here</span></div>
        </div>
      </div>
      <div className="login-panel">
        <form className="login-card" onSubmit={(e) => { e.preventDefault(); if (found.state === "found") void create(); }}>
          <div>
            <div style={{ fontSize: 22, fontWeight: 700, letterSpacing: "-.4px" }}>Post UTME Registration</div>
            <div className="hint" style={{ marginTop: 4 }}>Your JAMB registration number first. Everything else follows from it.</div>
          </div>
          <div className="field">
            <label htmlFor="rj">JAMB registration number</label>
            <input id="rj" className="tnum" value={num} onChange={(e) => setNum(e.target.value)} placeholder="202699176777GF" maxLength={15} autoComplete="off" spellCheck={false} />
            <div className="hint">{found.state === "idle" && num ? "Twelve digits and then two or three letters, exactly as JAMB issued it." : "Checked against the list JAMB sent the University. Nothing else is asked for until it is found."}</div>
          </div>
          {found.state === "nolist" ? (
            <Note kind="bad" title="Nobody can be verified yet, and so nobody is let through">
              The Academic Office has not uploaded the list of candidates JAMB sent for this session. Until it does, this screen cannot tell a real candidate from anybody who wandered onto it, and it will not guess. A Post-UTME roll that anyone may join is not a roll.
            </Note>
          ) : null}
          {found.state === "none" ? (
            <Note kind="bad" title="That number is not on the list JAMB sent the University">
              This is not a decision about you, and it is usually one of three things. <b>One:</b> a digit is wrong &mdash; the number is twelve digits and then two or three letters, and it is on your JAMB slip. <b>Two:</b> you did not choose this University on CAPS, in which case change your institution with JAMB first. <b>Three:</b> JAMB sends the list in tranches and yours has not reached us yet, in which case try again after forty-eight hours. <b>Do not travel to the campus to resolve this</b> &mdash; nobody at the gate can add you to a list that comes from JAMB.
            </Note>
          ) : null}
          {found.state === "registered" ? (
            <Note kind="info" title="An application account already exists for this number" action={<Link href="/login" className="btn btn--primary btn--sm">Sign in</Link>}>
              Sign in with the email and password you chose. A second account would invalidate both.
            </Note>
          ) : null}
          {found.state === "found" ? (
            <>
              <Note kind="ok" title={`Found on the ${found.list === "de" ? "Direct Entry" : "UTME"} list JAMB sent the University`}>
                Your name below is read from that list. It is <b>not</b> a field you fill in, because a name typed here would differ from the name JAMB holds and the two would be found to disagree at clearance, months from now. If it is wrong, it is wrong at JAMB: correct it there and it corrects itself here.
              </Note>
              <div className="field">
                <label>Surname and other names</label>
                <div className="readout">{found.name}</div>
                <div className="hint">From JAMB &middot; {key}</div>
              </div>
              {found.programme ? (
                <div className="field">
                  <label>Programme you chose</label>
                  <div className="readout">{found.programme}</div>
                  <div className="hint">As JAMB recorded it. Screening is against this programme.</div>
                </div>
              ) : null}
              {field("re", "Email address", "email",
                <input id="re" type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" autoComplete="off" spellCheck={false} required />,
                "Every notice about your application is sent here — including the offer, which lapses if it is not answered. Use an address you will still have in four years.")}
              {mailTypo(email) ? (
                <Note kind="info" title={`Did you mean ${mailTypo(email)}?`}>
                  One letter out in a provider&rsquo;s name is not a mistake anybody can see reading it back, and the address is still perfectly valid &mdash; it simply belongs to nobody. Nothing is refused here: if <span className="tnum">{email.split("@")[1]}</span> is right, carry on.
                </Note>
              ) : null}
              {field("rp", "Phone number", "phone",
                <input id="rp" className="tnum" type="tel" value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="0803 411 7725" inputMode="numeric" autoComplete="off" required />,
                phoneHint)}
              <div className="field">
                <label htmlFor="rw">Choose a password<span className="lreq">required</span></label>
                <div className="pwrow">
                  <input id="rw" type={show ? "text" : "password"} value={pw} onChange={(e) => setPw(e.target.value)} autoComplete="new-password" required />
                  <button type="button" className="pweye" aria-pressed={show ? "true" : "false"} onClick={() => setShow(!show)}>{show ? "Hide" : "Show"}</button>
                </div>
                {err.pw ? <div className="ferr">{err.pw}</div> : null}
              </div>
              <div className="field">
                <label htmlFor="rw2">Confirm password<span className="lreq">required</span></label>
                <input id="rw2" type={show ? "text" : "password"} value={pw2} onChange={(e) => setPw2(e.target.value)} autoComplete="new-password" required />
                {err.pw2 ? <div className="ferr">{err.pw2}</div> : null}
                <div className="hint">{show ? "Both boxes are showing. Nobody standing behind you should be able to read them." : "Asked twice because a password mistyped once locks you out of your own application on the morning of screening, and the portal cannot tell it from a stranger. Press Show if you would rather see what you typed."}</div>
              </div>
              {problem ? <ProblemNotice problem={problem} /> : null}
              <button className="btn btn--primary" type="submit" disabled={busy}>{busy ? "Creating your account…" : "Continue"}</button>
            </>
          ) : found.state !== "registered" ? (
            <>
              <button className="btn btn--primary" type="button" disabled style={{ opacity: 0.45, cursor: "not-allowed" }}>Continue</button>
              <div className="hint" style={{ textAlign: "center" }}>Enter your JAMB number to continue</div>
            </>
          ) : null}
          <Note kind="bad" title="The University sells nothing at the gate">
            No member of staff, agent or &ldquo;consultant&rdquo; can sell you a place, a higher score or a faster clearance. Every naira you owe is paid on this portal, to a reference this portal generates. Report any other demand to the Registrar.
          </Note>
          <div style={{ borderTop: "1px solid var(--line)", paddingTop: 14 }}>
            <Link href="/login" className="btn btn--ghost btn--sm" style={{ width: "100%" }}>I already have an account</Link>
          </div>
        </form>
      </div>
    </div>
  );
}
