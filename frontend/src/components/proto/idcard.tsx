/**
 * The student identity card, drawn to ISO/IEC 7810 ID-1 (85.6 × 54 mm), front
 * and back — a faithful port of proto/part25.html (idCardFront / idCardBack).
 * Every value is the student's own; a field the record does not hold is shown
 * as "—" rather than invented. The barcode is real Code 128-B of the borrower
 * number, so a scanner reads it.
 */

export interface IdCardData {
  name: string;
  matric: string;
  /** what the scanner reads — the borrower number, stable across replacements */
  barcode: string;
  /** the printed serial — changes on replacement */
  serial: string;
  faculty: string;
  prog: string;
  level: string;
  session: string;
  admitted: string;
  graduates: string;
  blood: string;
  expiresShort: string;
  kinPhone: string;
  photoSrc?: string | null;
  state?: "issued" | "blocked" | "expired";
}

/* ── Code 128-B, drawn to the module (proto barcodeSVG / c128*) ── */
const C128 = [
  "212222", "222122", "222221", "121223", "121322", "131222", "122213", "122312", "132212", "221213",
  "221312", "231212", "112232", "122132", "122231", "113222", "123122", "123221", "223211", "221132",
  "221231", "213212", "223112", "312131", "311222", "321122", "321221", "312212", "322112", "322211",
  "212123", "212321", "232121", "111323", "131123", "131321", "112313", "132113", "132311", "211313",
  "231113", "231311", "112133", "112331", "132131", "113123", "113321", "133121", "313121", "211331",
  "231131", "213113", "213311", "213131", "311123", "311321", "331121", "312113", "312311", "332111",
  "314111", "221411", "431111", "111224", "111422", "121124", "121421", "141122", "141221", "112214",
  "112412", "122114", "122411", "142112", "142211", "241211", "221114", "413111", "241112", "134111",
  "111242", "121142", "121241", "114212", "124112", "124211", "411212", "421112", "421211", "212141",
  "214121", "412121", "111143", "111341", "131141", "114113", "114311", "411113", "411311", "113141",
  "114131", "311141", "411131", "211412", "211214", "211232", "2331112",
];

function c128Modules(text: string): number[] {
  const vals: number[] = [104]; // Start B
  let sum = 104;
  for (let i = 0; i < text.length; i++) {
    let v = text.charCodeAt(i) - 32;
    if (v < 0 || v > 94) v = 63; // outside Code B, print '?'
    vals.push(v);
    sum += v * (i + 1);
  }
  vals.push(sum % 103); // check character
  vals.push(106); // stop
  const runs: number[] = [];
  for (const val of vals) for (const ch of C128[val]) runs.push(Number(ch));
  return runs;
}

function Barcode({ text, ink = "#111" }: { text: string; ink?: string }) {
  const runs = c128Modules(text);
  const total = runs.reduce((a, b) => a + b, 0);
  const quiet = 10;
  const units = total + quiet * 2;
  const bars: React.ReactNode[] = [];
  let x = quiet;
  let dark = true;
  runs.forEach((r, i) => {
    if (dark) bars.push(<rect key={i} x={x} y={0} width={r} height={38} />);
    x += r;
    dark = !dark;
  });
  return (
    <svg width="100%" height={38} viewBox={`0 0 ${units} 38`} preserveAspectRatio="none" shapeRendering="crispEdges" role="img" aria-label={`Barcode ${text}`}>
      <rect width={units} height={38} fill="#fff" />
      <g fill={ink}>{bars}</g>
    </svg>
  );
}

/* the verification QR (a fixed device mark, as in the prototype) */
function Qr() {
  return (
    <svg width="100%" height="100%" viewBox="0 0 29 29" shapeRendering="crispEdges" role="img" aria-label="Verification QR code">
      <rect width="29" height="29" fill="#fff" />
      <path fill="var(--ink)" d="M1 1h7v7H1V1Zm1 1v5h5V2H2Zm1 1h3v3H3V3Zm18-2h7v7h-7V1Zm1 1v5h5V2h-5Zm1 1h3v3h-3V3ZM1 21h7v7H1v-7Zm1 1v5h5v-5H2Zm1 1h3v3H3v-3ZM10 1h1v2h1V1h1v3h-1v1h-2V4h1V3h-1V1Zm4 2h1v1h2v1h-1v1h-2V5h1V4h-1V3Zm-4 4h2v1h1v1h-2v1h-1V7Zm4 1h1v1h1v2h-2V8Zm-4 4h1v1h2v-1h1v2h-1v1h-2v-1h-1v-1Zm5 0h2v1h-1v2h-1v-3Zm4 0h2v2h-1v1h-1v-3ZM10 16h1v1h1v-1h2v1h-1v1h-1v1h-2v-3Zm5 1h1v1h1v1h-2v-2Zm4-1h2v1h1v1h-2v1h-1v-3Zm4 1h2v2h-1v1h-1v-3ZM10 21h2v1h-1v2h1v1h-2v-4Zm4 0h1v2h1v-1h1v2h-1v1h-2v-4Zm5 1h1v1h2v1h-1v1h-2v-3Zm4 0h2v1h1v2h-1v-1h-2v-2ZM21 9h1v2h2v1h-1v1h-2V9Zm4 2h2v1h1v1h-2v1h-1v-3ZM10 9h1v1h1v1h-2V9Z" />
    </svg>
  );
}

function Field({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="idc__f">
      <span className="idc__l">{label}</span>
      <span className={"idc__v" + (mono ? " tnum" : "")}>{value || "—"}</span>
    </div>
  );
}

const CREST = "/crest.png";

export function IdCardFront({ c }: { c: IdCardData }) {
  const isVoid = c.state === "blocked" || c.state === "expired";
  return (
    <div className={"idc idc--front" + (isVoid ? " is-void" : "")}>
      <div className="idc__guilloche" />
      <div className="idc__wm"><img src={CREST} alt="" /></div>
      <div className="idc__head">
        <img src={CREST} alt="" style={{ width: 26, height: 26, objectFit: "contain", flexShrink: 0 }} />
        <div className="idc__uni">
          <span className="n">Rev. Fr. Moses Orshio Adasu University</span>
          <span className="a">Makurdi &middot; Benue State &middot; Nigeria</span>
        </div>
      </div>
      <div className="idc__rule"><i /><b /></div>
      <div className="idc__body">
        <div className="idc__photo">
          {c.photoSrc ? (
            <img src={c.photoSrc} alt="Holder's photograph" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
          ) : (
            <svg viewBox="0 0 100 124" width="100%" height="100%" role="img" aria-label="Holder's photograph">
              <rect width="100" height="124" fill="#D7E2E9" />
              <circle cx="50" cy="45" r="21" fill="#8FA5B4" />
              <path d="M15 124c0-21 15-34 35-34s35 13 35 34Z" fill="#8FA5B4" />
            </svg>
          )}
          <span className="idc__tag">Student</span>
        </div>
        <div className="idc__who">
          <div className="idc__name">{c.name}</div>
          <div className="idc__matric tnum">{c.matric}</div>
          <div className="idc__grid">
            <Field label="Faculty" value={c.faculty} />
            <Field label="Level" value={c.level} mono />
            <Field label="Programme" value={c.prog} />
            <Field label="Blood group" value={c.blood} mono />
            <Field label="Admitted" value={c.admitted} mono />
            <Field label="Graduates" value={c.graduates} mono />
          </div>
        </div>
      </div>
      <div className="idc__foot">
        <span>Session <b className="tnum">{c.session}</b> &middot; valid to <b className="tnum">{c.expiresShort}</b></span>
        <span className="idc__ser tnum">{c.serial}</span>
      </div>
      {isVoid ? <div className="idc__void">{c.state === "blocked" ? "Blocked" : "Expired"}</div> : null}
    </div>
  );
}

export function IdCardBack({ c }: { c: IdCardData }) {
  return (
    <div className="idc idc--back">
      <div className="idc__strip">Property of the University &middot; not transferable</div>
      <div className="idc__code">
        <Barcode text={c.barcode} />
        <div className="idc__cnum tnum">{c.barcode}</div>
      </div>
      <div className="idc__bcols">
        <div className="idc__terms">
          <b>Conditions</b>
          <p>This ID card must always be in the owner&rsquo;s possession for identification at the gates, examination or wherever identification is necessary.</p>
          <p>Any alteration or erasure renders this card invalid. Loss must be reported immediately to the Chief Security Officer of the University.</p>
        </div>
        <div className="idc__vfy">
          <div className="idc__qr"><Qr /></div>
          <div className="idc__vt">moaum.edu.ng/verify<br /><span className="tnum">{c.serial}</span></div>
          <div className="idc__kin">In an emergency<br /><b>{c.kinPhone}</b></div>
        </div>
      </div>
      <div className="idc__sig">
        <div><span />Holder&rsquo;s signature</div>
        <div><span />Registrar</div>
      </div>
    </div>
  );
}

export function IdCardPair({ c, big }: { c: IdCardData; big?: boolean }) {
  return (
    <div className={"idc__pair" + (big ? " is-big" : "")}>
      <div className="idc__side"><span className="idc__face">Front</span><IdCardFront c={c} /></div>
      <div className="idc__side"><span className="idc__face">Back</span><IdCardBack c={c} /></div>
    </div>
  );
}
