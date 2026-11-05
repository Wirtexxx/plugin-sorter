// Turns the repo's screenshots, icon and font into site/assets. Run with `npm run assets`.
import { copyFile, mkdir, readFile, access } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";
import { chromium } from "playwright";

const site = join(dirname(fileURLToPath(import.meta.url)), "..");
const docs = join(site, "../docs");
const out = join(site, "assets");
const font = join(site, "node_modules/@fontsource-variable/manrope");
const exists = (p) => access(p).then(() => true, () => false);

const webp = (from, to, width, height) =>
  sharp(join(docs, from))
    .resize(width, height, { fit: "cover", position: "top" })
    .webp({ quality: 82, alphaQuality: 90, effort: 6 })
    .toFile(join(out, to));

async function images() {
  await webp("screenshot.png", "app.webp", 1600);
  await webp("screenshot.png", "app-800.webp", 800);
  await webp("screenshot-cards.png", "app-cards.webp", 1600);
  await webp("screenshot-cards.png", "app-cards-800.webp", 800);
  const after = await webp("screenshot-fl-picker.png", "picker-after.webp", 1600);
  // Same size as "after", so the two pictures line up on the page.
  if (await exists(join(docs, "screenshot-fl-picker-before.png"))) {
    await webp("screenshot-fl-picker-before.png", "picker-before.webp", after.width, after.height);
  }
  await sharp(join(docs, "icon.png")).resize(256).png({ compressionLevel: 9, palette: true, quality: 90 })
    .toFile(join(out, "icon.png"));
}

// Plugin thumbnails cut from the real picker for the moving strip: [left, top] in the source.
const TILES = [
  [1175, 562], [62, 843], [1070, 652], [531, 83], [820, 843], [625, 562], [1323, 652], [440, 843],
  [186, 83], [1575, 652], [1498, 743], [945, 652], [322, 743], [314, 843], [1449, 652], [694, 843],
  [60, 83], [818, 652], [1365, 743], [567, 843], [188, 743], [188, 843],
];
const TILE = { width: 110, height: 66, gap: 22 };

async function strip() {
  const source = join(docs, "screenshot-fl-picker.png");
  const corners = Buffer.from(`<svg width="${TILE.width}" height="${TILE.height}"><rect width="${TILE.width}" height="${TILE.height}" rx="6"/></svg>`);
  const step = TILE.width + TILE.gap;
  const composites = await Promise.all(TILES.map(async ([left, top], i) => ({
    left: i * step,
    top: 0,
    input: await sharp(source)
      .extract({ left, top, width: TILE.width, height: TILE.height })
      .composite([{ input: corners, blend: "dest-in" }])
      .png().toBuffer(),
  })));
  await sharp({
    create: { width: TILES.length * step, height: TILE.height, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } },
  }).composite(composites).webp({ quality: 88, alphaQuality: 90, effort: 6 }).toFile(join(out, "strip.webp"));
}

async function fonts() {
  await mkdir(join(out, "fonts"), { recursive: true });
  for (const script of ["latin", "cyrillic"]) {
    await copyFile(join(font, `files/manrope-${script}-wght-normal.woff2`), join(out, `fonts/manrope-${script}.woff2`));
  }
  await copyFile(join(font, "LICENSE"), join(out, "fonts/OFL.txt"));
}

const dataUri = async (path, type) => `data:${type};base64,${(await readFile(path)).toString("base64")}`;

// The social card is drawn by a browser, because it needs Manrope and the page's own glow.
async function socialCard() {
  const [latin, icon, app] = await Promise.all([
    dataUri(join(out, "fonts/manrope-latin.woff2"), "font/woff2"),
    dataUri(join(out, "icon.png"), "image/png"),
    dataUri(join(out, "app.webp"), "image/webp"),
  ]);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1200, height: 630 } });
  await page.setContent(`<!doctype html><style>
@font-face { font-family: Manrope; src: url(${latin}) format("woff2"); font-weight: 200 800; }
* { box-sizing: border-box; margin: 0; }
body { width: 1200px; height: 630px; overflow: hidden; position: relative; background: #101014; color: #fff;
  font-family: Manrope, sans-serif; }
.glow { position: absolute; right: -180px; top: -40px; width: 1000px; height: 760px;
  background: radial-gradient(closest-side, rgba(150,84,255,.6), rgba(226,92,214,.24) 58%, transparent); }
.text { position: absolute; left: 68px; top: 64px; width: 580px; }
.brand { display: flex; align-items: center; gap: 14px; font-size: 28px; font-weight: 700; color: #ececf2; }
.brand img { width: 64px; height: 64px; }
h1 { font-size: 62px; line-height: 1.08; letter-spacing: -.03em; font-weight: 800; margin-top: 56px; }
em { font-style: normal; background: linear-gradient(90deg,#c79bff,#f08be0); -webkit-background-clip: text;
  background-clip: text; color: transparent; }
p { margin-top: 34px; font-size: 25px; font-weight: 500; color: #b8b8c6; }
.win { position: absolute; left: 690px; top: 76px; width: 720px; border-radius: 18px;
  box-shadow: 0 0 90px rgba(150,84,255,.5), 0 30px 60px rgba(0,0,0,.5); }
</style><div class="glow"></div>
<div class="text"><div class="brand"><img src="${icon}" alt="">Plugin Sorter</div>
<h1>The plugin manager <em>FL Studio on Mac</em> was missing</h1><p>Free and open source</p></div>
<img class="win" src="${app}" alt="">`, { waitUntil: "load" });
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: join(out, "og.png") });
  await browser.close();
}

await mkdir(out, { recursive: true });
await images();
await strip();
await fonts();
await socialCard();
