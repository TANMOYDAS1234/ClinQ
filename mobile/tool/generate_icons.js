/**
 * Derives every launcher icon and in-app logo asset from the master ClinIQ
 * artwork.
 *
 *   node tool/generate_icons.js
 *
 * Source: assets/brand/source/cliniq_logo.png — the full lockup (emblem +
 * wordmark + tagline) as supplied by the client.
 *
 * The wordmark is unreadable below about 120px, so the launcher icon is built
 * from the emblem alone. The full lockup is kept for the login screen, where
 * there is room for it.
 *
 * Uses the `sharp` already present in ../backend rather than adding an icon
 * generator to the app's own dependencies — this is a build-time asset step.
 */
const fs = require('node:fs/promises');
const path = require('node:path');

const sharp = require(path.join(__dirname, '..', '..', 'backend', 'node_modules', 'sharp'));

const ROOT = path.join(__dirname, '..');
const BRAND = path.join(ROOT, 'assets', 'brand');
const SOURCE = path.join(BRAND, 'source', 'clinq_logo.png');

/** Emblem band in the source image, measured from its content rows. */
const EMBLEM = { top: 173, bottom: 779 };

const ANDROID_LEGACY = {
  'mipmap-mdpi': 48, 'mipmap-hdpi': 72, 'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144, 'mipmap-xxxhdpi': 192,
};

/** Adaptive layers are 108dp; the launcher masks them down to roughly 72dp. */
const ANDROID_ADAPTIVE = {
  'mipmap-mdpi': 108, 'mipmap-hdpi': 162, 'mipmap-xhdpi': 216,
  'mipmap-xxhdpi': 324, 'mipmap-xxxhdpi': 432,
};

const IOS_ICONS = [
  ['Icon-App-20x20@1x.png', 20], ['Icon-App-20x20@2x.png', 40], ['Icon-App-20x20@3x.png', 60],
  ['Icon-App-29x29@1x.png', 29], ['Icon-App-29x29@2x.png', 58], ['Icon-App-29x29@3x.png', 87],
  ['Icon-App-40x40@1x.png', 40], ['Icon-App-40x40@2x.png', 80], ['Icon-App-40x40@3x.png', 120],
  ['Icon-App-60x60@2x.png', 120], ['Icon-App-60x60@3x.png', 180],
  ['Icon-App-76x76@1x.png', 76], ['Icon-App-76x76@2x.png', 152],
  ['Icon-App-83.5x83.5@2x.png', 167],
  ['Icon-App-1024x1024@1x.png', 1024],
];

const WHITE = { r: 255, g: 255, b: 255, alpha: 1 };

/**
 * Emblem only, tightly trimmed.
 *
 * Deliberately two passes: within a single pipeline sharp runs `trim` before
 * `extract`, so the crop would be measured against an already-shrunk image and
 * fail with "bad extract area".
 */
async function emblemBuffer() {
  const meta = await sharp(SOURCE).metadata();
  const cropped = await sharp(SOURCE)
    .extract({ left: 0, top: EMBLEM.top, width: meta.width, height: EMBLEM.bottom - EMBLEM.top })
    .png()
    .toBuffer();
  // Drop the surrounding white so the emblem can be centred on its own.
  return sharp(cropped).trim({ threshold: 12 }).png().toBuffer();
}

/** Full lockup, tightly trimmed. */
async function lockupBuffer() {
  return sharp(SOURCE).trim({ threshold: 12 }).png().toBuffer();
}

/**
 * Square icon: the emblem centred on a white plate.
 *
 * @param {number} size    output edge length
 * @param {number} inset   fraction of the plate left as margin around the emblem
 * @param {number} radius  corner radius as a fraction of size (0 = square)
 */
async function buildIcon(emblem, size, { inset = 0.14, radius = 0 } = {}) {
  const inner = Math.round(size * (1 - inset * 2));

  const scaled = await sharp(emblem)
    .resize(inner, inner, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .toBuffer();

  let plate = sharp({
    create: { width: size, height: size, channels: 4, background: WHITE },
  }).composite([{ input: scaled, gravity: 'center' }]);

  if (radius > 0) {
    const r = Math.round(size * radius);
    const mask = Buffer.from(
      `<svg width="${size}" height="${size}"><rect width="${size}" height="${size}" rx="${r}" ry="${r}" fill="#fff"/></svg>`,
    );
    plate = sharp(await plate.png().toBuffer()).composite([{ input: mask, blend: 'dest-in' }]);
  }

  return plate.png().toBuffer();
}

async function write(buf, outPath) {
  await fs.mkdir(path.dirname(outPath), { recursive: true });
  await fs.writeFile(outPath, buf);
}

async function main() {
  try {
    await fs.access(SOURCE);
  } catch {
    console.error(`Master artwork not found at ${SOURCE}`);
    process.exit(1);
  }

  const emblem = await emblemBuffer();
  const lockup = await lockupBuffer();
  const androidRes = path.join(ROOT, 'android', 'app', 'src', 'main', 'res');
  const iosDir = path.join(ROOT, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset');
  let count = 0;

  // Legacy Android icon — corners baked in, since pre-26 launchers do not mask.
  for (const [dir, size] of Object.entries(ANDROID_LEGACY)) {
    await write(await buildIcon(emblem, size, { inset: 0.12, radius: 0.2 }),
      path.join(androidRes, dir, 'ic_launcher.png'));
    count += 1;
  }

  // Adaptive foreground — square and unrounded; the launcher applies the mask.
  // Extra inset keeps the emblem inside the guaranteed-visible 66% safe zone.
  for (const [dir, size] of Object.entries(ANDROID_ADAPTIVE)) {
    await write(await buildIcon(emblem, size, { inset: 0.26, radius: 0 }),
      path.join(androidRes, dir, 'ic_launcher_foreground.png'));
    count += 1;
  }

  // iOS rejects icons with an alpha channel, and applies its own corner mask.
  for (const [name, size] of IOS_ICONS) {
    const buf = await buildIcon(emblem, size, { inset: 0.12, radius: 0 });
    await write(await sharp(buf).flatten({ background: WHITE }).png().toBuffer(),
      path.join(iosDir, name));
    count += 1;
  }

  // In-app assets.
  await write(await buildIcon(emblem, 512, { inset: 0.1, radius: 0.22 }), path.join(BRAND, 'logo.png'));
  await write(await sharp(emblem).resize(512, 512, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } }).png().toBuffer(),
    path.join(BRAND, 'logo_emblem.png'));
  await write(await sharp(lockup).resize({ width: 900, withoutEnlargement: true }).png().toBuffer(),
    path.join(BRAND, 'logo_lockup.png'));
  count += 3;

  console.log(`generated ${count} files from ${path.basename(SOURCE)}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
