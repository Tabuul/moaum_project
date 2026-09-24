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

const isCode = (t: string) => /^[A-Z][A-Z0-9 _]{2,}$/.test(t.trim()) && !/[a-z]/.test(t);

export function humanTitle(title: string | null | undefined, fallback = "The request was refused"): string {
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
