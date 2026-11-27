import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join, dirname, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

/* A server component that CALLS a function a "use client" module exports fails at render, in production with no message and a 500
   ("Attempted to call orgFromStructure() from the server but orgFromStructure is on the client", React error #441): the Summer desk's
   Students and Reports views did, from V779 to V787. A client module exports components and what only they use; whatever a server page
   needs too lives in a plain module. This reads every source file that is not a client module and refuses a lowercase VALUE imported
   (not a type, not a hook) from one that is. */

const SRC = resolve(dirname(fileURLToPath(import.meta.url)), "..");

function files(dir: string): string[] {
  const out: string[] = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...files(p));
    else if (/\.(ts|tsx)$/.test(name) && !/\.test\.(ts|tsx)$/.test(name)) out.push(p);
  }
  return out;
}

const clientCache = new Map<string, boolean>();
function isClient(path: string): boolean {
  const known = clientCache.get(path);
  if (known !== undefined) return known;
  let client = false;
  try {
    for (const line of readFileSync(path, "utf8").split("\n").slice(0, 12)) {
      const t = line.trim();
      if (!t || t.startsWith("//") || t.startsWith("/*") || t.startsWith("*")) continue;
      client = t.replace(/;$/, "") === '"use client"' || t.replace(/;$/, "") === "'use client'";
      break;
    }
  } catch { client = false; }
  clientCache.set(path, client);
  return client;
}

function target(from: string, spec: string): string | null {
  const base = spec.startsWith("@/") ? join(SRC, spec.slice(2)) : spec.startsWith(".") ? resolve(dirname(from), spec) : null;
  if (!base) return null;
  for (const ext of [".tsx", ".ts", `${sep}index.tsx`, `${sep}index.ts`]) if (existsSync(base + ext)) return base + ext;
  return null;
}

export function offenders(all: string[]): string[] {
  const found: string[] = [];
  const IMPORT = /import\s+(?!type\b)\{([^}]*)\}\s+from\s+["']([^"']+)["']/g;
  for (const f of all) {
    if (isClient(f)) continue;
    const text = readFileSync(f, "utf8");
    for (const m of text.matchAll(IMPORT)) {
      const to = target(f, m[2]);
      if (!to || !isClient(to)) continue;
      for (const raw of m[1].split(",")) {
        const item = raw.trim();
        if (!item || item.startsWith("type ")) continue;
        const name = item.split(/\s+as\s+/)[0].trim();
        if (/^[a-z]/.test(name) && !name.startsWith("use")) found.push(`${relative(SRC, f)} imports the function ${name} from the client module ${relative(SRC, to)}`);
      }
    }
  }
  return found;
}

test("no server module calls a function a client module exports", () => {
  assert.deepEqual(offenders(files(SRC)), []);
});
