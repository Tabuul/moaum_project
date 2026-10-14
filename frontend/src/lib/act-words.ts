/**
 * The word a button reads while its act is under way (components/proto/Btn): the label's first word, as the act being
 * done — "Save changes" reads "Saving…", "Approve" "Approving…", "Export CSV" "Preparing…", "Sign out" "Signing out…".
 * A label whose first word is not here keeps its own words beside the spinner.
 */
export const DOING: Record<string, string> = {
  accept: "Accepting", acknowledge: "Saving", activate: "Activating", add: "Adding", admit: "Admitting", allocate: "Allocating",
  apply: "Applying", approve: "Approving", archive: "Archiving", ask: "Sending", assign: "Assigning", attach: "Attaching",
  begin: "Starting", bind: "Binding", book: "Booking", build: "Building", calculate: "Calculating", cancel: "Cancelling",
  change: "Saving", chase: "Sending", check: "Checking", claim: "Claiming", clear: "Clearing", close: "Closing",
  compute: "Computing", confirm: "Confirming", continue: "Continuing", copy: "Copying", correct: "Correcting", create: "Creating",
  deactivate: "Deactivating", decide: "Saving", decline: "Declining", defer: "Deferring", delete: "Deleting", detach: "Detaching",
  disable: "Disabling", dismiss: "Dismissing", download: "Preparing", drop: "Dropping", enable: "Enabling", end: "Ending",
  enrol: "Enrolling", enroll: "Enrolling", enter: "Entering", escalate: "Escalating", export: "Preparing", finalise: "Finalising",
  finalize: "Finalising", find: "Finding", forward: "Forwarding", generate: "Generating", grant: "Granting", hold: "Holding",
  import: "Importing", invite: "Inviting", issue: "Issuing", join: "Joining", lift: "Lifting", link: "Linking", load: "Loading",
  lock: "Locking", log: "Logging", look: "Looking", mark: "Marking", matriculate: "Matriculating", merge: "Merging", move: "Moving",
  notify: "Sending", open: "Opening", pause: "Pausing", pay: "Initiating payment", post: "Posting", prepare: "Preparing",
  preview: "Checking", print: "Preparing", process: "Processing", promote: "Promoting", publish: "Publishing", put: "Saving",
  raise: "Raising", reassign: "Reassigning", rebuild: "Rebuilding", recalculate: "Recalculating", recommend: "Recommending",
  recompute: "Recomputing", reconcile: "Reconciling", record: "Recording", recover: "Recovering", refresh: "Refreshing",
  refund: "Refunding", register: "Registering", reject: "Rejecting", release: "Releasing", reload: "Loading", remind: "Sending",
  remove: "Removing", rename: "Renaming", reopen: "Reopening", replace: "Replacing", reply: "Sending", request: "Requesting",
  requery: "Checking", rerun: "Running", resend: "Resending", reserve: "Reserving", reset: "Resetting", resolve: "Resolving",
  restore: "Restoring", resume: "Resuming", retry: "Retrying", return: "Returning", reverse: "Reversing", revoke: "Revoking",
  run: "Running", save: "Saving", search: "Searching", send: "Sending", set: "Saving", settle: "Settling", sign: "Signing",
  start: "Starting", state: "Saving", stop: "Stopping", submit: "Submitting", suspend: "Suspending", swap: "Swapping",
  switch: "Switching", sync: "Syncing", take: "Taking", tell: "Sending", transfer: "Transferring", turn: "Turning",
  unbind: "Unbinding", unlink: "Unlinking", unlock: "Unlocking", unpublish: "Unpublishing", unsuspend: "Restoring",
  update: "Updating", upload: "Uploading", validate: "Validating", verify: "Verifying", waive: "Waiving", withdraw: "Withdrawing",
};

/* the thing acted on, kept where it says more than the verb alone: "Export PDF" reads "Preparing PDF…", "Verify payment"
   "Verifying payment…", "Start exam" "Starting exam…" */
const OBJECT: Record<string, string> = {
  pdf: "PDF", excel: "Excel", csv: "CSV", xlsx: "XLSX", payment: "payment", exam: "exam", examination: "examination",
  results: "results", scores: "scores", letter: "letter", report: "report", transcript: "transcript", certificate: "certificate",
  document: "document",
};

/** "Sign out" → "Signing out…", "Turn off" → "Turning off…", "Export to Excel" → "Preparing Excel…", "Set up" → "Saving…";
 *  null for a label whose first word is not an act this list knows */
export function doingWord(label: string): string | null {
  const m = /^([A-Za-z]+)(?:\s+(?:(in|out|up|on|off)\b|(?:(?:to|as|the|a)\s+)?([A-Za-z]+)))?/.exec(label.trim());
  if (!m) return null;
  const doing = DOING[m[1].toLowerCase()];
  if (!doing) return null;
  // "Sign in", "Sign out", "Turn off" keep their particle; "Set up" is simply "Saving…"
  if (m[2]) return `${doing}${doing !== "Saving" ? " " + m[2].toLowerCase() : ""}…`;
  const thing = m[3] ? OBJECT[m[3].toLowerCase()] : undefined;
  return `${doing}${thing && !doing.endsWith(" " + thing) ? " " + thing : ""}…`;
}
