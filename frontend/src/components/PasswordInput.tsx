"use client";

/**
 * A password field with an eye to show what is typed and hide it again (.pwrow / .pweye in prototype.css), each field its own.
 * The eye is the sign-in page's; it is a plain button, so it never submits the form, and it says what it does to a screen reader.
 */
import { useState, type InputHTMLAttributes } from "react";

const EYE = <><path d="M2.06 12.35a1 1 0 0 1 0-.7 10.75 10.75 0 0 1 19.88 0 1 1 0 0 1 0 .7 10.75 10.75 0 0 1-19.88 0" /><circle cx="12" cy="12" r="3" /></>;
const EYE_OFF = <><path d="M10.73 5.08A10.43 10.43 0 0 1 12 5c4.98 0 9.2 3.13 10.88 7.55a1 1 0 0 1 0 .7 10.97 10.97 0 0 1-1.44 2.49" /><path d="M14.08 14.16a3 3 0 0 1-4.24-4.24" /><path d="M17.48 17.5A10.75 10.75 0 0 1 1.12 12.55a1 1 0 0 1 0-.7 10.75 10.75 0 0 1 4.45-5.14" /><path d="m2 2 20 20" /></>;

export function PasswordInput({ id, className = "ctl", ...rest }: Omit<InputHTMLAttributes<HTMLInputElement>, "type"> & { id: string }) {
  const [show, setShow] = useState(false);
  const label = show ? "Hide password" : "Show password";
  return (
    <div className="pwrow">
      <input id={id} className={className} type={show ? "text" : "password"} autoCapitalize="none" autoCorrect="off" spellCheck={false} {...rest} />
      <button type="button" className="pweye" aria-controls={id} aria-pressed={show} aria-label={label} title={label} onClick={() => setShow((v) => !v)}>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{show ? EYE_OFF : EYE}</svg>
      </button>
    </div>
  );
}
