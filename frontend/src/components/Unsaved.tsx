"use client";

import { useEffect } from "react";
import { markUnsaved } from "@/lib/idle";

/**
 * V437: a form tells the idle-timeout warning that it holds unsaved changes, and how to save them. Rendered inside the form,
 * so the registration lives exactly as long as the form is on screen, and it reads the form's latest state on every render.
 * Leave `save` out where saving needs something only the person can give (a reason, a correction): the warning then says
 * the changes are unsaved without offering to save them.
 */
export function Unsaved({ name, dirty, save }: { name: string; dirty: boolean; save?: (() => Promise<unknown> | unknown) | null }) {
  useEffect(() => {
    markUnsaved(name, dirty, save ?? undefined);
    return () => markUnsaved(name, false);
  });
  return null;
}
