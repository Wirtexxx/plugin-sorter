import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { buildSite } from "../build.mjs";
import { page, RELEASE_IMAGES } from "../src/page.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const baseConfig = JSON.parse(await readFile(join(here, "../site.config.json"), "utf8"));

async function build(config = {}, extra = {}) {
  const outDir = await mkdtemp(join(tmpdir(), "ps-site-"));
  const assetsDir = await mkdtemp(join(tmpdir(), "ps-assets-"));
  await buildSite({ outDir, assetsDir, config: { ...baseConfig, ...config }, ...extra });
  const read = (p) => readFile(join(outDir, p), "utf8");
  return { outDir, read };
}

test("builds both pages", async () => {
  const { read } = await build();
  assert.match(await read("index.html"), /<html lang="en"/);
  assert.match(await read("ru/index.html"), /<html lang="ru"/);
});

test("sets canonical and hreflang", async () => {
  const { read } = await build();
  const en = await read("index.html");
  assert.ok(en.includes('<link rel="canonical" href="https://pluginsorter.com/">'));
  assert.ok(en.includes("https://pluginsorter.com/ru/"));
  const ru = await read("ru/index.html");
  assert.ok(ru.includes('<link rel="canonical" href="https://pluginsorter.com/ru/">'));
  for (const html of [en, ru]) {
    for (const l of ["en", "ru", "x-default"]) assert.ok(html.includes(`hreflang="${l}"`), l);
  }
});

test("writes sitemap robots and CNAME", async () => {
  const { read } = await build();
  const sitemap = await read("sitemap.xml");
  assert.ok(sitemap.includes("<loc>https://pluginsorter.com/</loc>"));
  assert.ok(sitemap.includes("<loc>https://pluginsorter.com/ru/</loc>"));
  assert.ok((await read("robots.txt")).includes("Sitemap: https://pluginsorter.com/sitemap.xml"));
  assert.equal((await read("CNAME")).trim(), "pluginsorter.com");
});

test("has valid structured data", async () => {
  const { read } = await build();
  for (const [file, copyFile] of [["index.html", "en"], ["ru/index.html", "ru"]]) {
    const html = await read(file);
    const copy = JSON.parse(await readFile(join(here, `../src/copy/${copyFile}.json`), "utf8"));
    const blocks = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)]
      .map((m) => JSON.parse(m[1]));
    const app = blocks.find((b) => b["@type"] === "SoftwareApplication");
    const faq = blocks.find((b) => b["@type"] === "FAQPage");
    assert.ok(app);
    assert.equal(app.offers.price, "0");
    assert.ok(faq);
    assert.equal(faq.mainEntity.length, copy.faq.length);
  }
});

test("has one h1 and social tags", async () => {
  const { read } = await build();
  const html = await read("index.html");
  assert.equal((html.match(/<h1[\s>]/g) || []).length, 1);
  for (const t of ["og:title", "og:image"]) assert.ok(html.includes(`property="${t}"`), t);
  assert.ok(html.includes('name="twitter:card"'));
});

test("hides donations without a Ko-fi link", async () => {
  const { read } = await build({ koFiUrl: "" });
  for (const f of ["index.html", "ru/index.html"]) {
    const html = await read(f);
    assert.ok(!html.includes("<dialog"));
    assert.ok(!html.includes("ko-fi.com"));
  }
});

test("shows donations with a Ko-fi link", async () => {
  const { read } = await build({ koFiUrl: "https://ko-fi.com/example" });
  const html = await read("index.html");
  assert.ok(html.includes("<dialog"));
  assert.ok(html.includes('href="https://ko-fi.com/example"'));
  assert.ok(html.includes('id="support-dialog"'));
  assert.ok(html.includes('id="support-fab"'));
});

test("without a Ko-fi link there is no floating button or script", async () => {
  const { read, outDir } = await build({ koFiUrl: "" });
  const html = await read("index.html");
  assert.ok(!html.includes("support-fab"));
  assert.ok(!html.includes("site.js"));
});

test("the page loads nothing from Ko-fi by itself", async () => {
  const { read, outDir } = await build();
  for (const f of ["index.html", "ru/index.html"]) {
    const html = await read(f);
    assert.ok(!/<iframe/.test(html), "no iframe in the markup");
    assert.ok(!/(src|srcset|data)="https?:\/\/[^"]*ko-fi/.test(html.replace(/data-embed-src="[^"]*"/g, "")));
    assert.ok(html.includes('src="/assets/site.js"'));
    assert.ok(/<script[^>]*src="\/assets\/site\.js"[^>]*defer/.test(html));
  }
  assert.match(await readFile(join(outDir, "assets/site.js"), "utf8"), /showModal/);
});

test("release build needs the before screenshot", async () => {
  const outDir = await mkdtemp(join(tmpdir(), "ps-site-"));
  const assetsDir = await mkdtemp(join(tmpdir(), "ps-assets-"));
  await assert.rejects(
    buildSite({ release: true, outDir, assetsDir, config: baseConfig }),
    /Missing picker-before\.webp/,
  );
});

test("release build needs every other referenced image", async () => {
  const assetsDir = await mkdtemp(join(tmpdir(), "ps-assets-"));
  const files = ["picker-before.webp", ...RELEASE_IMAGES.filter((f) => f !== "picker-before.webp")];
  for (const missing of files.slice(1)) {
    const outDir = await mkdtemp(join(tmpdir(), "ps-site-"));
    await rm(assetsDir, { recursive: true, force: true });
    await mkdir(assetsDir);
    for (const f of files) if (f !== missing) await writeFile(join(assetsDir, f), "x");
    await assert.rejects(
      buildSite({ release: true, outDir, assetsDir, config: baseConfig }),
      new RegExp(`Missing ${missing.replace(".", "\\.")}`),
    );
  }
});

test("release build passes with every image", async () => {
  const assetsDir = await mkdtemp(join(tmpdir(), "ps-assets-"));
  const outDir = await mkdtemp(join(tmpdir(), "ps-site-"));
  for (const f of RELEASE_IMAGES) await writeFile(join(assetsDir, f), "x");
  await buildSite({ release: true, outDir, assetsDir, config: baseConfig });
  const html = await readFile(join(outDir, "index.html"), "utf8");
  assert.ok(html.includes("/assets/picker-before.webp"));
  assert.ok(!html.includes("placeholder"));
});

test("the guard covers every image the pages reference", async () => {
  const { read } = await build();
  const html = (await read("index.html")) + (await read("ru/index.html"));
  const used = [...html.matchAll(/\/assets\/([\w-]+\.(?:webp|png))/g)].map((m) => m[1]);
  for (const f of new Set(used)) assert.ok(RELEASE_IMAGES.includes(f), f);
});

test("copies the stylesheet", async () => {
  const { read } = await build();
  assert.match(await read("assets/styles.css"), /@font-face/);
  assert.ok((await read("index.html")).includes('href="/assets/styles.css"'));
});

const shape = (v) => Array.isArray(v) ? v.map(shape)
  : v && typeof v === "object" ? Object.fromEntries(Object.keys(v).map((k) => [k, shape(v[k])]))
  : typeof v;

const readCopy = async (lang) => JSON.parse(await readFile(join(here, `../src/copy/${lang}.json`), "utf8"));

test("both languages have the same keys, in the same shape", async () => {
  assert.deepEqual(shape(await readCopy("ru")), shape(await readCopy("en")));
});

test("the copy does not promise a screenshot of every plugin", async () => {
  for (const lang of ["en", "ru"]) {
    const { hero, picker } = await readCopy(lang);
    assert.ok(!/every plugin|каждого плагина/i.test(hero.subtitle + picker.points[0]), lang);
    assert.ok(!/real interface of every|настоящий интерфейс каждого/i.test(picker.lead), lang);
    assert.match(picker.lead, /Audio Unit/, lang);
    assert.match(picker.points[1], /Audio Unit/, lang);
  }
});

test("the safety answer names the rescan and the password, in the search markup too", async () => {
  const { read } = await build();
  for (const [file, words] of [
    ["index.html", [/rescan/, /administrator password/, /normally/]],
    ["ru/index.html", [/просканировать/, /пароль администратора/, /обычно/]],
  ]) {
    const html = await read(file);
    const faq = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)]
      .map((m) => JSON.parse(m[1])).find((b) => b["@type"] === "FAQPage");
    const answer = faq.mainEntity[2].acceptedAnswer.text;
    for (const word of words) assert.match(answer, word);
  }
});

test("flat No cells stay narrow enough to be true whatever FL Studio has", async () => {
  for (const lang of ["en", "ru"]) {
    const rows = (await readCopy(lang)).compare.rows.filter((r) => r.fl[0] === "no");
    assert.ok(rows.length >= 5, lang);
    for (const r of rows) assert.ok(!/^[^,]+, [^,]+, /.test(r.label) || /CSV/.test(r.label), r.label);
  }
});

test("the rows the author has to check are named in LAUNCH.md", async () => {
  const launch = await readFile(join(here, "../LAUNCH.md"), "utf8");
  const rows = (await readCopy("ru")).compare.rows.slice(-5);
  for (const r of rows) assert.ok(launch.includes(`«${r.label}»`), r.label);
});

test("the status lamps name no real plugin on a warning", async () => {
  const { read } = await build();
  for (const f of ["index.html", "ru/index.html"]) {
    const lamps = (await read(f)).match(/<div class="lamps"[\s\S]*?<p class="lamps-note">/)[0];
    assert.ok(!/kHs|Kilohearts|OldReverb|Legacy Audio/.test(lamps));
  }
});

test("the dialog tells older macOS how to open the app", async () => {
  assert.match((await readCopy("en")).dialog.macNote, /right-click the app and choose Open/);
  assert.match((await readCopy("ru")).dialog.macNote, /правой кнопкой и выберите «Открыть»/);
});

test("the repo's own assets pass a release build, with the real before shot", async () => {
  const outDir = await mkdtemp(join(tmpdir(), "ps-site-"));
  await buildSite({ release: true, outDir });
  for (const f of ["index.html", "ru/index.html"]) {
    const html = await readFile(join(outDir, f), "utf8");
    assert.ok(html.includes('src="/assets/picker-before.webp"'));
    assert.ok(!html.includes('class="placeholder"'));
  }
});

test("the before shot is described as the mixed picker it is", async () => {
  for (const [lang, many] of [["en", /many third-party plugins/], ["ru", /многие сторонние плагины/]]) {
    const { picker, support } = await readCopy(lang);
    assert.match(picker.lead, many, lang);
    assert.match(picker.beforeAlt, many, lang);
    const said = [picker.lead, picker.beforeAlt, support.text].join(" ");
    assert.ok(!/wall of plain text|every plugin in my picker|стеной из названий|все плагины были/i.test(said), lang);
  }
});

test("escapes copy", () => {
  const copy = JSON.parse(JSON.stringify({ ...en() }));
  copy.hero.title = "<script>alert(1)</script>";
  const html = page(copy, {
    lang: "en", config: baseConfig, hasBefore: false,
    otherUrl: "https://pluginsorter.com/ru/", url: "https://pluginsorter.com/",
  });
  assert.ok(html.includes("&lt;script&gt;"));
  assert.ok(!html.includes("<script>alert(1)"));
});

function en() {
  return JSON.parse(requireText(join(here, "../src/copy/en.json")));
}
import { readFileSync } from "node:fs";
function requireText(p) { return readFileSync(p, "utf8"); }
