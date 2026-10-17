/**
 * V532: what the Mail server and Notices screens say about sending e-mail — a server that only receives mail, a From address
 * on another domain than the mailbox, and how long the waiting e-mail takes at the pace set. The server's answer decides;
 * these only warn before it is asked.
 */

/** the SMTP pace as the API gives it (a missing limit is no limit) */
export interface SmtpPace { perMinute?: number | null; perDay?: number | null; lastMinute: number; lastDay: number; allowance?: number | null }

/** a host Microsoft uses for incoming mail, which never takes the portal's sign-in to send */
export function smtpHostWarning(host: string): string | null {
  const h = host.trim().toLowerCase();
  if (h === "smtp.mail.outlook.com" || h.endsWith(".mail.protection.outlook.com")) {
    return "This is one of Microsoft's servers for incoming mail; it does not accept the portal signing in to send. Microsoft 365 sending is smtp.office365.com, port 587, STARTTLS.";
  }
  return null;
}

/** the address in "Name <address>" or a bare address, lower case */
export function addressOf(s: string): string {
  const m = s.match(/<([^>]+)>/);
  return (m ? m[1] : s).trim().toLowerCase();
}

function domainOf(address: string): string {
  const at = address.lastIndexOf("@");
  return at < 0 ? "" : address.slice(at + 1);
}

/** a From address on another domain than the mailbox: Microsoft 365 refuses it (SendAsDenied) unless the mailbox has Send As */
export function fromDomainWarning(username: string, from: string): string | null {
  const u = domainOf(addressOf(username));
  const f = domainOf(addressOf(from));
  if (!from.trim() || !u || !f || u === f) return null;
  return `The From address is on ${f}, the mailbox on ${u}. Microsoft 365 refuses that unless the mailbox has "Send As" on the From address; leave it empty to send as the mailbox. Send a test e-mail below to be sure.`;
}

/** how long the e-mail waiting takes at a day's limit, in words */
export function paceWords(pace: SmtpPace, waiting: number): string {
  const limits = `${pace.perMinute ? `${pace.perMinute.toLocaleString("en-GB")} a minute` : "no limit a minute"}, ${pace.perDay ? `${pace.perDay.toLocaleString("en-GB")} a day` : "no limit a day"}`;
  const tried = `Tried ${pace.lastMinute.toLocaleString("en-GB")} in the last minute and ${pace.lastDay.toLocaleString("en-GB")} in the last 24 hours`;
  const now = pace.allowance == null ? "" : `; ${pace.allowance.toLocaleString("en-GB")} more may go now`;
  let take = "";
  if (waiting > 0 && pace.perDay) {
    const days = Math.ceil(waiting / pace.perDay);
    take = ` At this pace the ${waiting.toLocaleString("en-GB")} e-mail${waiting === 1 ? "" : "s"} waiting take about ${days} day${days === 1 ? "" : "s"}.`;
  }
  return `${limits}. ${tried}${now}.${take}`;
}

/** a limit box read: empty is no limit, otherwise a whole number */
export function limitOf(s: string): number | null {
  const t = s.trim();
  return t === "" ? null : Number(t.replace(/[^0-9]/g, ""));
}
