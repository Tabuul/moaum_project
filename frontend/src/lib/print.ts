/**
 * Print one part of the page reliably, under the official document header (V320). The app's print
 * stylesheet hides the whole shell (`.shell`) so the page chrome does not print; the side effect is
 * that a plain window.print() from a button inside the shell prints a blank page. The central print
 * clones the target element into a hidden, same-origin iframe that carries the app's own stylesheets
 * and the institution's header and footer, and is NOT inside `.shell`, so it prints. Anything marked
 * `.no-print` (toolbars, buttons) is dropped.
 */
import { printElement } from "@/lib/document/html";
import type { DocumentProfileId } from "@/lib/document/profiles";

export function printNode(el: HTMLElement | null, heading?: string, profile: DocumentProfileId = "STANDARD_REPORT"): void {
  if (typeof window === "undefined") return;
  const title = (heading ?? document.title ?? "").trim();
  void printElement(el, { title }, profile);
}
