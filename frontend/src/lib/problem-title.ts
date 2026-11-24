/**
 * A refusal's title as a person reads it. The API now sends a human title with every refusal; this is the
 * safety net for an older API, or for any title that still arrives as a code ("AUTH BAD CREDENTIALS"):
 * the code's own words, in plain English.
 */
const KNOWN: Record<string, string> = {
  "AUTH BAD CREDENTIALS": "Wrong username or password",
  "AUTH LOCKED": "Account locked for now",
  "AUTH THROTTLED": "Too many attempts",
  "AUTH RESET TOKEN": "That reset link is not valid",
  "AUTH PASSWORD SHORT": "Password too short",
  "APP PASSWORD SHORT": "Password too short",
  "AUTH PASSWORD IS USERNAME": "The password cannot be the username",
  "AUTH USERNAME TAKEN": "That username is taken",
  "AUTH NO STUDENT ACCOUNT": "No student account yet",
  "PAY GATEWAY UNREACHABLE": "The payment gateway is not reachable",
  "PAY GATEWAY REFUSED": "The payment was refused",
  "PAY ALREADY CONFIRMED": "That payment is already confirmed",
  "REG UNITS OUT OF RANGE": "Units out of range",
  "REG STUDENT NOT ELIGIBLE": "Not eligible to register",
  "COLLEGE NOT MEMBER": "Not a College student",
  "COLLEGE YEAR NOT ENDED": "The year has not ended",
  "COLLEGE NOT YOUR LEVEL": "Not your level",
  "STUDENT RECORD CLOSED": "This record is closed",
  "IAM NO SUCH OFFICE": "No such office",
  "IAM GRANT NEEDS INSTRUMENT": "An instrument is needed",
};

/** V779: refusals whose words a person reads by their code, whatever title the server sent (a code the API's own titles do not know
 *  arrives as its bare words, "Credit reinstated", which says the opposite of what happened) — with the remedy to show when the
 *  refusal carries none */
export const CODE_WORDS: Record<string, { title: string; remedy?: { message: string; office: string } }> = {
  // the Bursar's reopen of a credit the student's own new selection used to pay the programme fee again (B2)
  SUMMER_CREDIT_REINSTATED: {
    title: "This credit pays the programme fee again",
    remedy: { message: "Nothing is reopened: the money pays the student's Summer programme fee. It is held as a credit again only if no Summer course of the student remains.", office: "Bursary" },
  },
  // the Summer Semester's examination session moved while open or released, or an open session moved into it (B4)
  SUMMER_EXAM_IDENTITY: {
    title: "The Summer's examination session keeps its place",
    remedy: { message: "Move the dates only. The Summer's examinations open from the Summer desk once its paid courses are verified; for another sitting, create a new examination session.", office: "Directorate of ICT" },
  },
};

const isCode = (t: string) => /^[A-Z][A-Z0-9 _]{2,}$/.test(t.trim()) && !/[a-z]/.test(t);

export function humanTitle(title: string | null | undefined, fallback = "The request was refused", code?: string | null): string {
  if (code && CODE_WORDS[code]) return CODE_WORDS[code].title;
  const t = (title ?? "").trim();
  if (!t) return fallback;
  if (!isCode(t)) return t;
  const key = t.replace(/_/g, " ").replace(/\s+/g, " ");
  if (KNOWN[key]) return KNOWN[key];
  const words = key.split(" ");
  const rest = words.length > 2 ? words.slice(1) : words;   // drop the module prefix when there is more to say
  const tail = rest.join(" ");
  if (/ SAYS WHY$/.test(key)) return "A reason is needed";
  if (/ MINUTE REQUIRED$/.test(key)) return "A minute is needed";
  if (/ ROWS$/.test(key)) return "The file's rows could not be read";
  if (/ RANGE$/.test(key)) return `${sentence(rest.slice(0, -1).join(" ") || "Value")} out of range`;
  if (/ SIZE$/.test(key)) return "The file is too large";
  if (/ TYPE$/.test(key)) return "That file type is not accepted";
  if (/ ENCODING$/.test(key)) return "The file could not be read";
  return sentence(tail);
}

function sentence(s: string): string {
  const w = s.toLowerCase().trim();
  return w ? w.charAt(0).toUpperCase() + w.slice(1) : s;
}

/** the remedy a refusal shows: its own, or the one its code carries here */
export function problemRemedy(problem: { code?: string | null; remedy?: { message: string; office: string } | null } | null | undefined): { message: string; office: string } | undefined {
  return problem?.remedy ?? (problem?.code ? CODE_WORDS[problem.code]?.remedy : undefined);
}
