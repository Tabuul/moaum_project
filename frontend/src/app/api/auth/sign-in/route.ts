import { NextRequest, NextResponse } from "next/server";
import { API_URL } from "@/lib/api";
import { OFFICE_COOKIE } from "@/lib/offices";
import { SESSION_COOKIE, cookieOptions } from "@/lib/session";

/**
 * One door for everybody. The number typed says who is signing in:
 *   MOAUM/XXX/YY/NNNN                 a student, on the matriculation number
 *   12 digits + 2–3 letters, APP/…    an applicant, on the JAMB or application number
 *   anything else                     a member of staff, on the staff number or email —
 *                                     and, failing that, an applicant on an email address, a
 *                                     postgraduate applicant on the old portal's number (V709), or a JUPEB
 *                                     student uploaded from the old portal on its number (V718)
 * The token goes into a cookie the browser cannot read; the office cookie says
 * which side of the portal opens.
 */
const MATRIC = /^MOAUM?\/[A-Z0-9]{2,6}(\/[A-Z0-9]{2,6})?\/[0-9]{2}\/[0-9]{1,8}$/i;   // MOAU/FAC[/PROG]/YY/SEQ (V263), or MOAUM/DEPT/YY/NNNN (V064)
/* the admission number an admitted candidate carries before matriculation: MOAUM/ADM/YY/NNNNNN.
   It opens the student door too, so they pay school fees and register courses under it. */
const ADMISSION = /^MOAUM\/ADM\/[0-9]{2}\/[0-9]{6}$/i;
const JAMB = /^[0-9]{12}[A-Z]{2,3}$/i;
const APPLICATION = /^APP\/[0-9]{2}\/[0-9]{6}$/i;
/* a postgraduate application number: PG/YY/NNNNNN — the PG applicant's own door (they also sign in on their email) */
const PG_APPLICATION = /^PG\/[0-9]{2}\/[0-9]{6}$/i;
/* a JUPEB application number: JUPEB/APP/YYYY/NNNNNN (V339) — the JUPEB candidate's own door, applicant to student to result
   (they also sign in on their email) */
const JUPEB_APPLICATION = /^JUPEB\/APP\/[0-9]{4}\/[0-9]{6}$/i;
/* a JUPEB candidate's token is an applicant's; this cookie tells the home page to open the JUPEB portal for them */
const JUPEB_COOKIE = "moaum_jupeb";
/* a legacy old-portal matriculation number carried over from the old portal — BSU/…, MOAU/…, and the
   like: two-to-six letters, one to four more segments, then digits. It opens the student door too, so a
   migrated student signs in; a rare staff number of the same shape falls back to the staff door. */
const LEGACY_MATRIC = /^[A-Z]{2,6}(\/[A-Z0-9]{2,6}){1,4}\/[0-9]{2,7}$/i;

type Kind = "staff" | "student" | "applicant" | "pgapplicant" | "jupeb";

async function upstream(path: string, body: unknown, request: NextRequest): Promise<Response | null> {
  return fetch(`${API_URL}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-forwarded-for": request.headers.get("x-forwarded-for") ?? "" },
    body: JSON.stringify(body ?? {}),
    cache: "no-store",
  }).catch(() => null);
}

function problem(text: string, status: number, contentType: string | null) {
  return new NextResponse(text, { status, headers: { "content-type": contentType ?? "application/problem+json" } });
}

/** the problem code a door refused with, or null — read from a copy, which leaves the body for later */
async function codeOf(r: Response): Promise<string | null> {
  try {
    const code = (JSON.parse(await r.clone().text()) as { code?: unknown }).code;
    return typeof code === "string" ? code : null;
  } catch {
    return null;
  }
}

/* V718: whether a door that refused knows the account — locked, a temporary password spent or standing (any 422 but "do not
   match"): that door's answer is the one for the person, in place of the staff door's. */
async function knowsTheAccount(r: Response): Promise<boolean> {
  if (r.status !== 422) return false;
  const code = await codeOf(r);
  return code !== null && code !== "AUTH_BAD_CREDENTIALS";
}

/* V724: the student door's refusals of a fresh admit the student portal's fee gate holds — the school fees unpaid, not yet stated,
   or the acceptance fee's balance owed. The door says them only once the password has opened the record. */
const HELD_AT_THE_FEE_GATE = ["STUDENT_PORTAL_HELD_FEES", "STUDENT_PORTAL_FEES_NOT_AVAILABLE", "STUDENT_PORTAL_ACCEPTANCE_BALANCE"];

export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
  const identifier = String(body?.identifier ?? body?.username ?? body?.matricNo ?? "").trim();
  const password = typeof body?.password === "string" ? body.password : "";
  const preferredOffice = typeof body?.office === "string" ? body.office : undefined;

  let kind: Kind = MATRIC.test(identifier) || ADMISSION.test(identifier) ? "student"
    : PG_APPLICATION.test(identifier) ? "pgapplicant"
    : JUPEB_APPLICATION.test(identifier) ? "jupeb"
    : JAMB.test(identifier) || APPLICATION.test(identifier) ? "applicant" : "staff";
  /* a legacy old-portal matric was not matched above (only MOAUM/… is) — route it to the student door,
     and fall back to staff if it turns out to be a staff number of the same shape */
  const legacyMatric = kind === "staff" && !identifier.includes("@") && LEGACY_MATRIC.test(identifier);
  let r: Response | null;
  /* V718: the doors that refused but know the account — the first of them answers when no door opens */
  const known: Response[] = [];
  if (kind === "student") {
    r = await upstream("/api/v1/student-auth/sign-in", { matricNo: identifier, password }, request);
  } else if (kind === "pgapplicant") {
    r = await upstream("/api/v1/pg/sign-in", { identifier, password }, request);
  } else if (kind === "jupeb") {
    r = await upstream("/api/v1/jupeb/sign-in", { identifier, password }, request);
  } else if (legacyMatric) {
    const asStudent = await upstream("/api/v1/student-auth/sign-in", { matricNo: identifier, password }, request);
    if (asStudent && asStudent.ok) {
      r = asStudent;
      kind = "student";
    } else {
      r = await upstream("/api/v1/auth/sign-in", { username: identifier, password, office: preferredOffice }, request);
      /* V709: an old-portal postgraduate number may have this shape too */
      if (r && (r.status === 422 || r.status === 429)) {
        const pg = await upstream("/api/v1/pg/sign-in", { identifier, password }, request);
        if (pg && pg.ok) {
          r = pg;
          kind = "pgapplicant";
        }
      }
    }
  } else if (kind === "applicant") {
    /* the same JAMB/application number opens the student dashboard once the candidate is on the
       register; try the student door first, and fall back to the applicant portal if they are not
       a student yet (offer not accepted, or not brought onto the register). */
    const asStudent = await upstream("/api/v1/student-auth/sign-in", { matricNo: identifier, password }, request);
    if (asStudent && asStudent.ok) {
      r = asStudent;
      kind = "student";
    } else {
      r = await upstream("/api/v1/applicant/sign-in", { identifier, password }, request);
      /* V724: the student door held the record at the fee gate (said only after the password matched) and the applicant door does
         not take the same password — a student account whose password has since changed: the student door's words are the true
         ones (pay the fees, or the acceptance balance, on the applicant dashboard), never "do not match" */
      if (r && !r.ok && asStudent && !asStudent.ok && HELD_AT_THE_FEE_GATE.includes((await codeOf(asStudent)) ?? "")
          && (await codeOf(r)) === "AUTH_BAD_CREDENTIALS") {
        r = asStudent;
      }
    }
  } else {
    r = await upstream("/api/v1/auth/sign-in", { username: identifier, password, office: preferredOffice }, request);
    /* an email address is also how an applicant signs in: the same wrong answer either way, so try the other doors —
       and when the staff door has refused this connection for a while (429, V359), the other doors keep their own count */
    if (r && (r.status === 422 || r.status === 429) && identifier.includes("@")) {
      const again = await upstream("/api/v1/applicant/sign-in", { identifier, password }, request);
      if (again && again.ok) {
        r = again;
        kind = "applicant";
      } else {
        if (again && (await knowsTheAccount(again))) known.push(again);
        /* and, last, the postgraduate applicant's door — they sign in on the email they applied with */
        const pg = await upstream("/api/v1/pg/sign-in", { identifier, password }, request);
        if (pg && pg.ok) {
          r = pg;
          kind = "pgapplicant";
        } else {
          if (pg && (await knowsTheAccount(pg))) known.push(pg);
          /* and the JUPEB candidate, on the email they applied with (V339) */
          const jupeb = await upstream("/api/v1/jupeb/sign-in", { identifier, password }, request);
          if (jupeb && jupeb.ok) {
            r = jupeb;
            kind = "jupeb";
          } else if (jupeb && (await knowsTheAccount(jupeb))) {
            known.push(jupeb);
          }
        }
      }
    } else if (r && (r.status === 422 || r.status === 429)) {
      /* V709: a number of no shape the page knows that is no staff number: the old portal's postgraduate application number
         (S00220260204082731 and the like), which the postgraduate door finds a migrated applicant by */
      const pg = await upstream("/api/v1/pg/sign-in", { identifier, password }, request);
      if (pg && pg.ok) {
        r = pg;
        kind = "pgapplicant";
      } else {
        if (pg && (await knowsTheAccount(pg))) known.push(pg);
        /* V718: or the old portal's JUPEB application number (S007202609174486 and the like), which the JUPEB door finds an
           uploaded student by */
        const jupeb = await upstream("/api/v1/jupeb/sign-in", { identifier, password }, request);
        if (jupeb && jupeb.ok) {
          r = jupeb;
          kind = "jupeb";
        } else if (jupeb && (await knowsTheAccount(jupeb))) {
          known.push(jupeb);
        }
      }
    }
    /* V718: no door opened — the one that knows the account answers (locked, a temporary password spent or standing) in place of
       the staff door's "do not match" or throttle, which is all a number of no shape the page knows was told before; the staff
       door's own refusal of an account it knows (locked, a retired first password) stands */
    if (r && !r.ok && known.length > 0 && !(await knowsTheAccount(r))) r = known[0];
  }
  if (!r) return NextResponse.json({ status: 503, title: "The portal API is not reachable" }, { status: 503 });
  const text = await r.text();
  if (!r.ok) return problem(text, r.status, r.headers.get("content-type"));

  const signed = JSON.parse(text) as Record<string, unknown>;
  const seconds = Math.max(60, Math.floor((new Date(String(signed.expiresAt)).getTime() - Date.now()) / 1000));
  let office: string;
  let name: string;
  let home: string;
  let mustChange = false;
  if (kind === "student") {
    office = "student";
    name = `${signed.surname}, ${signed.otherNames}`;
    mustChange = signed.mustChange === true;
    home = mustChange ? "/student/password" : "/student";
  } else if (kind === "applicant") {
    office = "applicant";
    name = `${signed.surname}, ${signed.otherNames}`;
    /* V687: signed in on a temporary password from the University: their own password first */
    mustChange = signed.mustChange === true;
    home = mustChange ? "/applicant/password" : "/applicant";
  } else if (kind === "pgapplicant") {
    office = "applicant";
    name = `${signed.surname}, ${signed.otherNames}`;
    /* V706: the University reset the password to the application number: their own password first */
    mustChange = signed.mustChange === true;
    home = mustChange ? "/pg/portal/password" : "/pg/portal";
  } else if (kind === "jupeb") {
    office = "applicant";
    name = `${signed.surname}, ${signed.otherNames}`;
    /* V718: a student uploaded from the old portal signed in on the application number: the portal asks their own password first */
    mustChange = signed.mustChange === true;
    home = "/jupeb/portal";
  } else {
    const offices = (signed.offices as { code: string }[] | undefined) ?? [];
    office = preferredOffice && offices.some((o) => o.code === preferredOffice) ? preferredOffice : offices[0]?.code ?? "";
    name = `${signed.surname}, ${signed.givenNames}`;
    mustChange = signed.mustChange === true;
    home = mustChange ? "/account/password" : "/";
  }
  const response = NextResponse.json({ kind, home, mustChange, name, office, offices: signed.offices ?? [] });
  response.cookies.set(SESSION_COOKIE, String(signed.token), cookieOptions(seconds));
  if (office) response.cookies.set(OFFICE_COOKIE, office, { ...cookieOptions(seconds), httpOnly: false });
  if (kind === "jupeb") response.cookies.set(JUPEB_COOKIE, "1", { ...cookieOptions(seconds), httpOnly: false });
  else response.cookies.delete(JUPEB_COOKIE);
  return response;
}
