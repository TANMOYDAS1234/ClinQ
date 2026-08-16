import sharp from 'sharp';

/**
 * Turning a photographed signature into ink on transparency.
 *
 * A doctor signs paper and photographs it with a phone. That photo is never
 * evenly lit: the sheet is brighter under the lamp and grey in the hand's
 * shadow, and the whole thing may sit well below "white" — a mid-grey page is
 * completely normal.
 *
 * The first version keyed on absolute luminance, which is why it failed on a
 * real photo. Anything darker than the fixed "paper" threshold stayed opaque,
 * so a shaded sheet came through as a grey rectangle with the signature on it —
 * exactly what a black-and-white filter would produce, and the opposite of what
 * is wanted.
 *
 * This works on LOCAL contrast instead. The page's own illumination is
 * estimated with a heavy blur, and each pixel is compared against its own
 * neighbourhood rather than against a constant. Ink is dark *relative to the
 * paper around it*, which stays true whether the photo is bright, dim or
 * unevenly lit — the same trick a document scanner uses.
 */

/// Below this fraction of the local page brightness a pixel is certainly ink.
const INK_RATIO = 0.62;

/// At or above this fraction it is certainly paper. Between the two the alpha
/// ramps, which is what keeps the soft edge of a pen stroke from turning into a
/// jagged cut-out.
const PAPER_RATIO = 0.86;

/// Plausibility bounds. These separate ink-on-paper from a blank page or a
/// photograph. They are NOT an identity check: no measurement here can tell
/// whose hand held the pen, and a check that implied otherwise would be a
/// guarantee with nothing behind it.
const MIN_INK_RATIO = 0.0015;
const MAX_INK_RATIO = 0.45;

/// Longest edge the mask is computed at. Big enough to keep a thin pen stroke,
/// small enough that the blur below stays cheap.
const WORK_EDGE = 1400;

/**
 * Greyscale pixels plus a blurred copy of the same, which stands in for "how
 * bright the page is around here".
 */
async function planes(buffer) {
  const base = sharp(buffer, { failOn: 'none' })
    .rotate()
    .greyscale()
    .resize({ width: WORK_EDGE, height: WORK_EDGE, fit: 'inside', withoutEnlargement: true });

  const { data, info } = await base.clone().raw().toBuffer({ resolveWithObject: true });

  // Sigma scaled to the image: the blur has to be wide enough to erase the
  // signature itself and leave only the lighting behind it. Too small and the
  // strokes appear in the background estimate, which cancels them out and the
  // signature disappears.
  const sigma = Math.max(8, Math.round(Math.max(info.width, info.height) / 22));
  const { data: bg } = await base
    .clone()
    .blur(sigma)
    .raw()
    .toBuffer({ resolveWithObject: true });

  return { data, bg, width: info.width, height: info.height, channels: info.channels };
}

/**
 * Alpha per pixel, from local contrast. 255 = ink, 0 = paper.
 */
function buildAlpha({ data, bg, width, height, channels }) {
  const alpha = Buffer.alloc(width * height);
  for (let i = 0, p = 0; p < alpha.length; i += channels, p += 1) {
    const local = bg[i] || 1;
    const ratio = data[i] / local;

    if (ratio <= INK_RATIO) {
      alpha[p] = 255;
    } else if (ratio >= PAPER_RATIO) {
      alpha[p] = 0;
    } else {
      alpha[p] = Math.round(255 * ((PAPER_RATIO - ratio) / (PAPER_RATIO - INK_RATIO)));
    }
  }
  return alpha;
}

function inkFraction(alpha) {
  let ink = 0;
  for (let i = 0; i < alpha.length; i += 1) if (alpha[i] > 128) ink += 1;
  return alpha.length === 0 ? 0 : ink / alpha.length;
}

/**
 * Assesses whether [buffer] plausibly holds a signature.
 *
 * Measured on the same local-contrast mask the cut-out uses, so the check and
 * the result agree: if this says there is ink, the cut-out will find it.
 */
export async function assessSignature(buffer) {
  const p = await planes(buffer);
  const ratio = inkFraction(buildAlpha(p));

  if (ratio < MIN_INK_RATIO) {
    return {
      ok: false,
      inkRatio: ratio,
      reason:
        'No signature found. Photograph it on plain paper, filling most of the frame, with the whole signature in shot.',
    };
  }
  if (ratio > MAX_INK_RATIO) {
    return {
      ok: false,
      inkRatio: ratio,
      reason:
        'This looks like a photograph rather than a signature on paper. Use a flat, well-lit shot of the signature alone.',
    };
  }
  return { ok: true, inkRatio: ratio, reason: null };
}

/**
 * Removes the paper, leaving the ink on transparency.
 *
 * The ink is flattened to near-black rather than kept at its photographed
 * colour: a signature shot under warm light comes out brown, and brown ink on
 * a printed prescription reads as a scan of a document rather than a signature
 * on one.
 */
export async function makeSignatureTransparent(buffer) {
  const p = await planes(buffer);
  const alpha = buildAlpha(p);
  const { width, height } = p;

  const ink = await sharp({
    create: { width, height, channels: 3, background: { r: 12, g: 18, b: 38 } },
  })
    .raw()
    .toBuffer();

  // PNG, not WebP: the prescription PDF composites this, and PNG alpha is what
  // every PDF writer handles without surprises.
  const composed = await sharp(ink, { raw: { width, height, channels: 3 } })
    .joinChannel(alpha, { raw: { width, height, channels: 1 } })
    .png()
    .toBuffer();

  // Trim the transparent margin so the stored asset is the signature and not
  // the sheet it happened to sit on — it then fills its box on the page.
  const trimmed = await sharp(composed)
    .trim({ threshold: 1 })
    .png()
    .toBuffer()
    .catch(() => composed);

  const meta = await sharp(trimmed).metadata();
  return { buffer: trimmed, width: meta.width ?? width, height: meta.height ?? height };
}
