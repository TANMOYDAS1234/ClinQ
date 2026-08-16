import sharp from 'sharp';

/**
 * Turning a photographed signature into something a prescription can carry.
 *
 * A doctor signs a sheet of paper and photographs it. Dropped straight onto a
 * prescription that is a grey rectangle sitting over the layout, with the
 * paper's own shade and shadows visible — it reads as a photo pasted on a
 * document rather than a signature on it.
 *
 * So the paper is removed: ink is kept, everything lighter becomes
 * transparent, and the result composites onto the page like real ink.
 */

/// Luminance at or above which a pixel counts as paper rather than ink.
/// Deliberately generous: phone photos of white paper often sit around 200-230
/// under indoor light, and a stricter cut left grey haze around every stroke.
const PAPER_LUMA = 168;

/// Below this a pixel is unambiguously ink and stays fully opaque. Between the
/// two it fades, which is what keeps the antialiased edge of a pen stroke from
/// turning into a jagged cut-out.
const INK_LUMA = 96;

/**
 * What a signature is allowed to look like.
 *
 * These bound a plausibility check, NOT an identity check. They can tell ink on
 * paper from a blank page or a selfie; they cannot tell whose hand held the pen.
 * Anything stricter would be a claim the code cannot back.
 */
const MIN_INK_RATIO = 0.002; // ~blank page
const MAX_INK_RATIO = 0.45; // a photo of a face/scene, or a scribbled-out page

/**
 * Assesses whether [buffer] plausibly holds a signature.
 *
 * Returns `{ ok, reason, inkRatio }`. `ok: false` is advisory — the caller
 * decides whether to refuse the upload or simply warn — because a real
 * signature written very lightly can fall under the floor, and refusing a
 * doctor's genuine signature is worse than accepting a doubtful one.
 */
export async function assessSignature(buffer) {
  const { data, info } = await sharp(buffer)
    .greyscale()
    .resize({ width: 600, withoutEnlargement: true })
    .raw()
    .toBuffer({ resolveWithObject: true });

  let ink = 0;
  for (let i = 0; i < data.length; i += info.channels) {
    if (data[i] < INK_LUMA) ink += 1;
  }
  const total = data.length / info.channels;
  const inkRatio = total === 0 ? 0 : ink / total;

  if (inkRatio < MIN_INK_RATIO) {
    return {
      ok: false,
      inkRatio,
      reason: 'This looks blank. Photograph the signature on plain paper, filling most of the frame.',
    };
  }
  if (inkRatio > MAX_INK_RATIO) {
    return {
      ok: false,
      inkRatio,
      reason: 'This looks like a photograph rather than a signature. Use a clear shot of the signature on plain paper.',
    };
  }
  return { ok: true, inkRatio, reason: null };
}

/**
 * Removes the paper, leaving the ink on transparency.
 *
 * The alpha channel is built from luminance rather than by keying a single
 * colour: paper is never one flat value in a phone photo — it shades off toward
 * the corners and under the hand — so a colour key leaves a bright patch in the
 * middle and a dark ring around the edge. A luminance ramp handles the whole
 * gradient at once, and keeps the soft edge of each stroke.
 *
 * The ink is also flattened to near-black. A signature photographed under warm
 * light comes out brown, and a brown signature on a printed prescription looks
 * scanned rather than signed.
 */
export async function makeSignatureTransparent(buffer) {
  const src = sharp(buffer, { failOn: 'none' }).rotate();
  const meta = await src.metadata();

  // Trimmed to the ink before anything else, so the stored asset is the
  // signature and not the sheet of paper it happens to sit on.
  const grey = await src
    .clone()
    .greyscale()
    .resize({ width: 1200, withoutEnlargement: true })
    .raw()
    .toBuffer({ resolveWithObject: true });

  const { data, info } = grey;
  const { width, height } = info;
  const alpha = Buffer.alloc(width * height);

  for (let i = 0, p = 0; i < data.length; i += info.channels, p += 1) {
    const luma = data[i];
    if (luma <= INK_LUMA) {
      alpha[p] = 255;
    } else if (luma >= PAPER_LUMA) {
      alpha[p] = 0;
    } else {
      // Linear fade across the band, so stroke edges stay soft.
      alpha[p] = Math.round(255 * ((PAPER_LUMA - luma) / (PAPER_LUMA - INK_LUMA)));
    }
  }

  // Near-black ink at the mask's shape. PNG, not WebP: the prescription PDF
  // composites this, and PNG alpha is the format every PDF writer handles
  // without surprises.
  const ink = await sharp({
    create: {
      width,
      height,
      channels: 3,
      background: { r: 12, g: 18, b: 38 },
    },
  })
    .raw()
    .toBuffer();

  const out = await sharp(ink, { raw: { width, height, channels: 3 } })
    .joinChannel(alpha, { raw: { width, height, channels: 1 } })
    .png()
    .toBuffer();

  // Trim the transparent margin so the signature fills its box on the page.
  const trimmed = await sharp(out).trim({ threshold: 1 }).png().toBuffer().catch(() => out);

  return { buffer: trimmed, width: meta.width ?? width, height: meta.height ?? height };
}
