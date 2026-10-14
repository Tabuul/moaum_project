/**
 * What the person started and is waiting for: one watch over the page's own requests, installed once for every screen
 * (components/proto/ActivityBar). Each request the portal sends to itself — the API through /api/bff, a sign-in or
 * sign-out through /api/auth, the next screen's content when a link or the router moves — is counted while it is in
 * flight, and the button (or form) whose click or submission sent it is held busy until it settles:
 *
 *  - the portal's Btn and IcoBtn (components/proto/Btn) read this state: a spinner, the act's own word ("Saving…",
 *    "Approving…"), aria-busy, and disabled until the act settles — a double-click never sends an act twice;
 *  - any other button, and a submitted form, reads aria-busy and data-busy (a spinner on a .btn, the waiting cursor
 *    elsewhere); a second click on it, or a second submission of the form (Enter in a field), is stopped while the
 *    first is under way;
 *  - the activity bar at the top of the page shows while anything the person asked for is still loading.
 *
 * The state is the request's own: it begins when the request is sent and ends when the server answers or the request
 * fails, never on a timer. A request is tied to a button by the event being handled when it was sent (window.event): the
 * click on the button, or the submission of the form (its submitter too). Requests the person did not ask for are not
 * counted: the X-Background polls (lib/idle), the router's prefetches, keepalive beacons, and everything inside an
 * examination room, where answers are saved quietly as the candidate works (a candidate is never held at a button).
 */

type Listener = () => void;

const listeners = new Set<Listener>();
const owners = new Map<Element, number>();
let inflight = 0;
let installed = false;

function emit() {
  for (const l of listeners) l();
}

export function subscribe(l: Listener): () => void {
  listeners.add(l);
  return () => { listeners.delete(l); };
}

/** requests the person asked for, in flight now */
export function inFlight(): number {
  return inflight;
}

/** true while a request this element's click (or this form's submission) sent is in flight */
export function isBusy(el: Element | null | undefined): boolean {
  return !!el && (owners.get(el) ?? 0) > 0;
}

/** the examination room saves answers in the background; nothing there is held or shown as loading */
export function quietPath(pathname: string): boolean {
  return /\/cbt\/room\//.test(pathname);
}

function header(input: RequestInfo | URL, init: RequestInit | undefined, name: string): string | null {
  const h = init?.headers ?? (input instanceof Request ? input.headers : undefined);
  if (!h) return null;
  if (h instanceof Headers) return h.get(name);
  if (Array.isArray(h)) {
    const hit = h.find(([k]) => k.toLowerCase() === name.toLowerCase());
    return hit ? hit[1] : null;
  }
  for (const k of Object.keys(h)) if (k.toLowerCase() === name.toLowerCase()) return (h as Record<string, string>)[k];
  return null;
}

/** a request the person is waiting for: the portal's own origin, not a background poll, a prefetch or a beacon */
export function watched(input: RequestInfo | URL, init?: RequestInit): boolean {
  if (typeof window === "undefined" || quietPath(window.location.pathname)) return false;
  let url: URL;
  try {
    url = new URL(input instanceof Request ? input.url : String(input), window.location.href);
  } catch {
    return false;
  }
  if (url.origin !== window.location.origin || url.pathname.startsWith("/_next/")) return false;
  if (init?.keepalive || (input instanceof Request && input.keepalive)) return false;
  if (header(input, init, "X-Background")) return false;
  if (header(input, init, "Next-Router-Prefetch") || header(input, init, "Next-Router-Segment-Prefetch")) return false;
  return true;
}

const ACTIVATING = "button, [role='button'], input[type='submit'], input[type='button']";

/** the button whose click, the form (and its submitter) whose submission, or the file field or list whose change is being
 *  handled now */
function ownersNow(): Element[] {
  const ev = (window as unknown as { event?: Event }).event;
  if (!ev || !(ev.target instanceof Element)) return [];
  if (ev.type === "submit") {
    const s = (ev as SubmitEvent).submitter;
    return s ? [ev.target, s] : [ev.target];
  }
  if (ev.type === "click") {
    const b = ev.target.closest(ACTIVATING);
    return b ? [b] : [];
  }
  if (ev.type === "change" && (ev.target instanceof HTMLInputElement || ev.target instanceof HTMLSelectElement)) return [ev.target];
  return [];
}

/* a Btn (data-act) draws its own busy state from isBusy; any other element is marked here */
function hold(els: Element[]) {
  for (const el of els) {
    const n = (owners.get(el) ?? 0) + 1;
    owners.set(el, n);
    if (n === 1 && !el.hasAttribute("data-act")) {
      el.setAttribute("data-busy", "");
      el.setAttribute("aria-busy", "true");
    }
  }
}

function release(els: Element[]) {
  for (const el of els) {
    const n = (owners.get(el) ?? 1) - 1;
    if (n > 0) {
      owners.set(el, n);
      continue;
    }
    owners.delete(el);
    if (!el.hasAttribute("data-act")) {
      el.removeAttribute("data-busy");
      el.removeAttribute("aria-busy");
    }
  }
}

/** installs the watch once: window.fetch counted, and a busy button's second click (or a busy form's submission) stopped */
export function installActivity(): void {
  if (installed || typeof window === "undefined") return;
  installed = true;
  const original = window.fetch.bind(window);
  window.fetch = function watchedFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
    if (!watched(input, init)) return original(input, init);
    const els = ownersNow();
    inflight++;
    hold(els);
    emit();
    const settle = () => {
      inflight--;
      release(els);
      emit();
    };
    let p: Promise<Response>;
    try {
      p = original(input, init);
    } catch (e) {
      settle();
      throw e;
    }
    // the next screen's content streams in after its headers: a navigation is under way until the last of it has come
    // (read from a copy, taken before the router reads its own); any other request has settled once the server answered
    const screen = header(input, init, "RSC") === "1";
    p.then((r) => {
      if (screen && r.body) r.clone().arrayBuffer().then(settle, settle);
      else settle();
    }, settle);
    return p;
  };
  // the act is already under way: a second click on its button, or a second submission of its form (Enter in a field),
  // is stopped before the screen's own handler sees it
  window.addEventListener("click", (e) => {
    const b = e.target instanceof Element ? e.target.closest(ACTIVATING) : null;
    if (b && b.hasAttribute("data-busy")) {
      e.preventDefault();
      e.stopImmediatePropagation();
    }
  }, true);
  window.addEventListener("submit", (e) => {
    if (e.target instanceof Element && e.target.hasAttribute("data-busy")) {
      e.preventDefault();
      e.stopImmediatePropagation();
    }
  }, true);
}
