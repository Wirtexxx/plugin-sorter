import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { serveBuild } from "./helpers.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const PAGES = [
  { path: "/", lang: "en", h1: "The plugin manager FL Studio on Mac was missing",
    title: "Free FL Studio plugin manager for Mac | Plugin Sorter" },
  { path: "/ru/", lang: "ru", h1: "Менеджер плагинов, которого не хватало в FL Studio на Mac",
    title: "Менеджер плагинов FL Studio для Mac | Plugin Sorter" },
];

let browser, site;
before(async () => {
  browser = await chromium.launch();
  site = await serveBuild();
});
after(async () => {
  await browser?.close();
  await site?.close();
});

async function open(path, options = {}) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, ...options });
  const page = await context.newPage();
  page.setDefaultTimeout(5000);
  const requests = [];
  page.on("request", (r) => requests.push(r.url()));
  await page.goto(site.url + path, { waitUntil: "load" });
  return { page, requests, done: () => context.close() };
}

for (const { path, lang, h1, title } of PAGES) {
  test(`${path} uses the exact headline and title`, async () => {
    const { page, done } = await open(path);
    const text = await page.locator("h1").innerText();
    assert.equal(text.replace(/\s+/g, " ").trim(), h1);
    assert.equal(await page.title(), title);
    await done();
  });

  test(`${path} keeps a clean heading order`, async () => {
    const { page, done } = await open(path);
    const levels = await page.$$eval("h1,h2,h3,h4", (hs) =>
      hs.filter((h) => !h.closest("dialog")).map((h) => Number(h.tagName[1])));
    assert.equal(levels.filter((l) => l === 1).length, 1);
    levels.forEach((l, i) => {
      if (i) assert.ok(l <= levels[i - 1] + 1, `h${levels[i - 1]} followed by h${l}`);
    });
    assert.ok(await page.locator("#features h2").count() === 1);
    assert.ok(await page.locator("#features h3").count() >= 6);
    await done();
  });

  for (const width of [320, 390, 768, 1440]) {
    test(`${path} has no horizontal scroll at ${width}`, async () => {
      const { page, done } = await open(path, { viewport: { width, height: 800 } });
      const { scroll, inner } = await page.evaluate(() => ({
        scroll: document.documentElement.scrollWidth, inner: window.innerWidth,
      }));
      assert.ok(scroll <= inner, `${scroll} > ${inner}`);
      // scrollWidth can hide overflow that clipping parents cut off, so check the boxes themselves.
      const over = await page.evaluate(() => {
        const sel = "h1, [data-gradient], a.btn, a.btn-ghost, button, td, th";
        return [...document.querySelectorAll(sel)]
          .filter((el) => !el.closest("dialog, .hero-media") && el.getClientRects().length)
          .map((el) => ({ el, right: el.getBoundingClientRect().right }))
          .filter(({ right }) => right > innerWidth + 0.5)
          .map(({ el, right }) => `${el.tagName}.${el.className} right=${right.toFixed(1)}`);
      });
      assert.deepEqual(over, []);
      await done();
    });
  }

  test(`${path} gives all images alt and size`, async () => {
    const { page, done } = await open(path);
    const images = await page.$$eval("img", (imgs) => imgs.map((i) => ({
      src: i.getAttribute("src"),
      alt: i.getAttribute("alt"),
      hidden: i.getAttribute("aria-hidden"),
      width: i.getAttribute("width"),
      height: i.getAttribute("height"),
    })));
    assert.ok(images.length >= 3);
    for (const img of images) {
      assert.ok(img.width && img.height, `${img.src} has no size`);
      assert.ok(img.alt !== null, `${img.src} has no alt`);
      if (img.alt === "") assert.equal(img.hidden, "true", `${img.src} has an empty alt`);
      const res = await page.request.get(site.url + img.src);
      assert.equal(res.status(), 200, img.src);
    }
    await done();
  });

  test(`${path} sizes each image like the file it shows`, async () => {
    const { page, done } = await open(path);
    await page.$$eval("img", (imgs) => Promise.all(imgs.map((i) => {
      i.loading = "eager";
      return i.decode();
    })));
    const wrong = await page.$$eval("img", (imgs) => imgs
      .filter((i) => Math.abs(i.naturalWidth / i.naturalHeight - i.width / i.height) > 0.02)
      .map((i) => i.currentSrc));
    assert.deepEqual(wrong, []);
    await done();
  });

  test(`${path} makes no external requests`, async () => {
    const { requests, done } = await open(path);
    const external = requests.filter((u) => !u.startsWith(site.url) && !u.startsWith("data:"));
    assert.deepEqual(external, []);
    await done();
  });

  test(`${path} hosts Manrope for its script`, async () => {
    const { page, requests, done } = await open(path);
    const family = await page.evaluate(() => getComputedStyle(document.body).fontFamily);
    assert.match(family, /^Manrope/);
    const script = lang === "ru" ? "cyrillic" : "latin";
    assert.ok(requests.some((u) => u.endsWith(`manrope-${script}.woff2`)), script);
    assert.ok(await page.evaluate(() => document.fonts.check('800 16px Manrope')));
    await done();
  });

  test(`${path} animates, and stops for reduced motion`, async () => {
    const names = (page) => page.evaluate(() => {
      const found = [];
      for (const el of document.querySelectorAll("*")) {
        for (const pseudo of [null, "::before", "::after"]) {
          const name = getComputedStyle(el, pseudo).animationName;
          if (name !== "none") found.push(`${el.tagName}.${el.className} ${pseudo ?? ""} ${name}`);
        }
      }
      return found;
    });
    const moving = await open(path);
    assert.ok((await names(moving.page)).length > 0, "nothing animates");
    await moving.done();
    const calm = await open(path, { reducedMotion: "reduce" });
    assert.deepEqual(await names(calm.page), []);
    await calm.done();
  });

  test(`${path} says it is for Mac on a phone`, async () => {
    const { page, done } = await open(path, { viewport: { width: 390, height: 800 } });
    const copy = JSON.parse(await readFile(join(here, `../src/copy/${lang}.json`), "utf8"));
    const note = page.getByText(copy.hero.note, { exact: true }).first();
    assert.ok(await note.isVisible());
    assert.match(await note.innerText(), /Mac/);
    await done();
  });

  test(`${path} keeps the copy honest`, async () => {
    const { page, done } = await open(path);
    const text = (await page.evaluate(() => document.documentElement.textContent)).toLowerCase();
    for (const bad of ["full replacement", "only tool", "полная замена", "полной заменой", "единственн"]) {
      assert.ok(!text.includes(bad), bad);
    }
    await done();
  });

  test(`${path} repeats the download at the end and marks the macOS warning`, async () => {
    const { page, done } = await open(path);
    assert.ok(await page.locator("a[data-download]").count() >= 3);
    const last = await page.locator("a[data-download]").last().boundingBox();
    const support = await page.locator("#support").boundingBox();
    assert.ok(last.y > support.y, "no download after the support block");
    assert.equal(await page.locator("#install [data-macos]").count(), 2);
    await done();
  });

  test(`${path} has a slot for a future video`, async () => {
    const { page, done } = await open(path);
    assert.equal(await page.locator("#hero .hero-media").count(), 1);
    await done();
  });

  test(`${path} shows the card view and the skins`, async () => {
    const { page, done } = await open(path);
    assert.equal(await page.locator('#features img[src*="app-cards"]').count(), 1);
    assert.equal(await page.locator("#features .skin").count(), 4);
    await done();
  });

  for (const width of [390, 1440]) {
    test(`${path} meets AA contrast at ${width}`, async () => {
      const { page, done } = await open(path, { viewport: { width, height: 900 } });
      const failures = await page.evaluate(() => {
        const parse = (c) => {
          const m = c.match(/[\d.]+/g).map(Number);
          return { rgb: m.slice(0, 3), a: m[3] ?? 1 };
        };
        const lum = ([r, g, b]) => {
          const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
          return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
        };
        const ratio = (a, b) => (Math.max(lum(a), lum(b)) + 0.05) / (Math.min(lum(a), lum(b)) + 0.05);
        const over = (top, a, under) => top.map((v, i) => v * a + under[i] * (1 - a));
        // Every layer from the page background up to the element, so translucent cards count.
        const backdrop = (el) => {
          const chain = [];
          for (let n = el; n; n = n.parentElement) chain.unshift(n);
          return chain.reduce((under, n) => {
            const { rgb, a } = parse(getComputedStyle(n).backgroundColor);
            return over(rgb, a, under);
          }, [0, 0, 0]);
        };
        const bad = [];
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        while (walker.nextNode()) {
          const el = walker.currentNode.parentElement;
          if (!walker.currentNode.textContent.trim() || el.closest("script,dialog,[data-gradient]")) continue;
          const style = getComputedStyle(el);
          if (style.display === "none" || style.visibility === "hidden") continue;
          const { rgb, a } = parse(style.color);
          if (a === 0) continue;
          const back = backdrop(el);
          const value = ratio(over(rgb, a, back), back);
          const size = parseFloat(style.fontSize);
          const large = size >= 24 || (size >= 18.66 && Number(style.fontWeight) >= 700);
          if (value < (large ? 3 : 4.5)) bad.push(`${value.toFixed(2)} ${el.tagName}: ${el.textContent.trim().slice(0, 40)}`);
        }
        return bad;
      });
      assert.deepEqual(failures, []);
      await done();
    });
  }
}

test("white on the button gradient meets AA at both ends", () => {
  const lum = (hex) => {
    const c = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
      .map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
  };
  for (const end of ["#7A45F5", "#B13BE0"]) assert.ok(1.05 / (lum(end) + 0.05) >= 4.5, end);
});

test("the language switch leads to the other page", async () => {
  const { page, done } = await open("/");
  await page.locator('header a[hreflang="ru"]').click();
  await page.waitForURL("**/ru/");
  assert.equal(await page.locator("html").getAttribute("lang"), "ru");
  await done();
});

test("the donation dialog is styled when Ko-fi is set", async (t) => {
  const withKoFi = await serveBuild({ config: { koFiUrl: "https://ko-fi.com/example" } });
  t.after(withKoFi.close);
  const context = await browser.newContext({ viewport: { width: 390, height: 800 } });
  t.after(() => context.close());
  const page = await context.newPage();
  await page.goto(withKoFi.url, { waitUntil: "load" });
  await page.evaluate(() => document.querySelector("#support-dialog").showModal());
  const box = await page.locator("dialog").boundingBox();
  assert.ok(box.x >= 0 && box.x + box.width <= 390);
  assert.notEqual(await page.locator("dialog").evaluate((d) => getComputedStyle(d).backgroundColor), "rgb(255, 255, 255)");
});

// ---- Support dialog and floating button ----
const CFG = JSON.parse(await readFile(join(here, "../site.config.json"), "utf8"));
const KOFI_STUB = "<!doctype html><title>stub</title><body style='font-family:sans-serif;background:#f9f9f9;color:#222'><h1>Ko-fi form (stub)</h1>";

/** Opens a page of `s` with the file and Ko-fi routes stubbed, so no test touches the network. */
async function openStubbed(s, path = "/", options = {}) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, ...options });
  const page = await context.newPage();
  page.setDefaultTimeout(5000);
  const requests = [];
  page.on("request", (r) => requests.push(r.url()));
  await context.route(/^https:\/\/ko-fi\.com\//, (r) =>
    r.fulfill({ status: 200, contentType: "text/html", body: KOFI_STUB }));
  await context.route(CFG.downloadUrl, (r) =>
    r.fulfill({ status: 200, headers: { "content-disposition": 'attachment; filename="PluginSorter.dmg"' }, body: "dmg" }));
  await page.goto(s.url + path, { waitUntil: "load" });
  const kofiRequests = () => requests.filter((u) => u.startsWith("https://ko-fi.com/"));
  return { page, requests, kofiRequests, done: () => context.close() };
}

const dialogOpen = (page) => page.locator("#support-dialog").evaluate((d) => d.open);
const scrollPastHero = (page) =>
  page.evaluate(() => window.scrollTo(0, document.querySelector("#hero").getBoundingClientRect().bottom + scrollY + 400));

for (const path of ["/", "/ru/"]) {
  test(`${path} download starts and dialog opens`, async () => {
    const { page, requests, done } = await openStubbed(site, path);
    const download = page.waitForEvent("download");
    await page.locator("#hero a[data-download]").click();
    await download;
    assert.ok(requests.includes(CFG.downloadUrl));
    assert.equal(await dialogOpen(page), true);
    assert.equal(await page.locator("#support-dialog").getAttribute("aria-modal"), null);
    await done();
  });
}

test("every download button opens the dialog", async () => {
  const { page, done } = await openStubbed(site);
  const count = await page.locator("a[data-download]").count();
  assert.ok(count >= 3);
  for (let i = 0; i < count; i++) {
    await page.locator("a[data-download]").nth(i).scrollIntoViewIfNeeded();
    await page.locator("a[data-download]").nth(i).click();
    assert.equal(await dialogOpen(page), true, `button ${i}`);
    await page.keyboard.press("Escape");
    assert.equal(await dialogOpen(page), false);
  }
  await done();
});

test("the dialog closes with the cross, Esc and a click on the backdrop", async () => {
  const { page, done } = await openStubbed(site);
  const open = () => page.locator("#hero a[data-download]").click();
  await open();
  await page.locator("#support-dialog [data-close]").click();
  assert.equal(await dialogOpen(page), false);
  await open();
  await page.keyboard.press("Escape");
  assert.equal(await dialogOpen(page), false);
  await open();
  await page.mouse.click(4, 4);
  assert.equal(await dialogOpen(page), false);
  await open();
  await page.locator("#support-dialog h2:visible").click();
  assert.equal(await dialogOpen(page), true, "a click inside must not close it");
  await done();
});

test("keyboard focus goes into the dialog and back to the button", async () => {
  const { page, done } = await openStubbed(site);
  const button = page.locator("#hero a[data-download]");
  await button.focus();
  await page.keyboard.press("Enter");
  assert.equal(await page.evaluate(() => !!document.activeElement.closest("#support-dialog")), true);
  await page.keyboard.press("Escape");
  assert.equal(await button.evaluate((b) => b === document.activeElement), true);
  await done();
});

for (const [path, copyFile] of [["/", "en"], ["/ru/", "ru"]]) {
  test(`${path} dialog shows the Mac note and Ko-fi attribution`, async () => {
    const copy = JSON.parse(await readFile(join(here, `../src/copy/${copyFile}.json`), "utf8"));
    const { page, done } = await openStubbed(site, path);
    await page.locator("#hero a[data-download]").click();
    assert.ok(await page.getByText(copy.dialog.macNote).isVisible());
    assert.ok(await page.getByText(copy.dialog.title).isVisible());
    assert.ok(await page.getByText(copy.dialog.embedNote).isVisible());
    assert.equal(await page.getByText(copy.dialog.supportTitle).isVisible(), false);
    await done();
  });
}

test("download links work without JavaScript", async () => {
  const { page, done } = await openStubbed(site, "/", { javaScriptEnabled: false });
  const hrefs = await page.$$eval("a[data-download]", (as) => as.map((a) => a.getAttribute("href")));
  assert.ok(hrefs.length >= 3);
  for (const h of hrefs) assert.equal(h, CFG.downloadUrl);
  assert.equal(await page.locator("#support-fab").isVisible(), false);
  await done();
});

test("without a Ko-fi link there is no dialog, no button and no script", async (t) => {
  const bare = await serveBuild({ config: { koFiUrl: "" } });
  t.after(bare.close);
  const { page, requests, done } = await openStubbed(bare);
  assert.equal(await page.locator("#support-dialog, #support-fab").count(), 0);
  assert.equal(await page.locator("script[src]").count(), 0);
  const download = page.waitForEvent("download");
  await page.locator("#hero a[data-download]").click();
  await download;
  assert.ok(requests.includes(CFG.downloadUrl));
  await done();
});

test("Ko-fi is only requested when the dialog opens and the form stays after closing", async () => {
  const { page, kofiRequests, requests, done } = await openStubbed(site);
  assert.equal(kofiRequests().length, 0);
  assert.equal(await page.locator("iframe").count(), 0);
  await page.locator("#hero a[data-download]").click();
  const frame = page.locator("iframe#kofiframe");
  await frame.waitFor();
  assert.equal(await page.locator("iframe").count(), 1);
  assert.equal(await frame.getAttribute("src"), CFG.koFiEmbedUrl);
  const en = JSON.parse(await readFile(join(here, "../src/copy/en.json"), "utf8"));
  assert.equal(await frame.getAttribute("title"), en.dialog.supportTitle);
  assert.equal(await frame.getAttribute("referrerpolicy"), "strict-origin-when-cross-origin");
  await page.frameLocator("#kofiframe").getByText("Ko-fi form (stub)").waitFor();
  assert.equal(kofiRequests().length, 1);
  await page.keyboard.press("Escape");
  await page.locator("#hero a[data-download]").click();
  assert.equal(await page.locator("iframe").count(), 1);
  assert.equal(kofiRequests().length, 1, "reopening must not reload the form");
  assert.ok(!requests.some((u) => /overlay-widget|storage\.ko-fi/.test(u)));
  await done();
});

for (const [path, copyFile] of [["/", "en"], ["/ru/", "ru"]]) {
  test(`${path} names the form frame in its own language`, async () => {
    const copy = JSON.parse(await readFile(join(here, `../src/copy/${copyFile}.json`), "utf8"));
    const { page, done } = await openStubbed(site, path);
    await page.locator("#hero a[data-download]").click();
    assert.equal(await page.locator("#kofiframe").getAttribute("title"), copy.dialog.supportTitle);
    await done();
  });

  test(`${path} shows the plain Ko-fi link above the form, inside an 800px viewport`, async () => {
    const { page, done } = await openStubbed(site, path, { viewport: { width: 1280, height: 800 } });
    await page.locator("#hero a[data-download]").click();
    const link = page.locator(`#support-dialog a[href="${CFG.koFiUrl}"]`);
    assert.equal(await link.getAttribute("target"), "_blank");
    assert.match(await link.getAttribute("rel"), /noopener/);
    const [l, f] = await Promise.all([link.boundingBox(), page.locator("#kofiframe").boundingBox()]);
    assert.ok(l.y + l.height <= f.y + 1, "the link must come before the form");
    assert.ok(l.y >= 0 && l.y + l.height <= 800, `link ends at ${l.y + l.height}`);
    await done();
  });
}

test("the form does not push the dialog around when it arrives", async () => {
  const { page, done } = await openStubbed(site);
  await page.locator("#hero a[data-download]").click();
  const height = () => page.locator("#support-dialog").evaluate((d) => d.scrollHeight);
  const before = await height();
  await page.locator("#kofiframe").waitFor();
  assert.ok(Math.abs((await height()) - before) <= 1);
  await done();
});

test("a dialog closed at once does not ask Ko-fi for the form", async () => {
  const { page, kofiRequests, done } = await openStubbed(site);
  await page.locator("#hero a[data-download]").click();
  await page.keyboard.press("Escape");
  await page.waitForTimeout(700);
  assert.equal(await page.locator("iframe").count(), 0);
  assert.equal(kofiRequests().length, 0);
  await done();
});

test("the floating button appears after the hero and opens the dialog without a download", async () => {
  for (const [path, copyFile] of [["/", "en"], ["/ru/", "ru"]]) {
    const copy = JSON.parse(await readFile(join(here, `../src/copy/${copyFile}.json`), "utf8"));
    const { page, requests, done } = await openStubbed(site, path);
    const fab = page.locator("#support-fab");
    assert.equal(await fab.evaluate((b) => b.tagName), "BUTTON");
    assert.equal(await fab.isVisible(), false);
    await scrollPastHero(page);
    await fab.waitFor({ state: "visible" });
    assert.equal((await fab.innerText()).trim(), copy.dialog.fab);
    await fab.click();
    assert.equal(await dialogOpen(page), true);
    assert.ok(await page.getByText(copy.dialog.supportTitle).isVisible());
    assert.equal(await page.getByText(copy.dialog.title).isVisible(), false);
    assert.equal(await page.getByText(copy.dialog.macNote).isVisible(), false);
    assert.ok(!requests.includes(CFG.downloadUrl));
    await page.keyboard.press("Escape");
    assert.equal(await fab.evaluate((b) => b === document.activeElement), true);
    await page.evaluate(() => scrollTo(0, 0));
    await fab.waitFor({ state: "hidden" });
    await done();
  }
});

test("the floating button hides while the support block is on screen", async () => {
  const { page, done } = await openStubbed(site);
  const fab = page.locator("#support-fab");
  await scrollPastHero(page);
  await fab.waitFor({ state: "visible" });
  await page.locator("#support").scrollIntoViewIfNeeded();
  await page.evaluate(() => document.querySelector("#support").scrollIntoView({ block: "center" }));
  await fab.waitFor({ state: "hidden" });
  await done();
});

test("the floating button stays on screen and out of the way at 320", async () => {
  const { page, done } = await openStubbed(site, "/", { viewport: { width: 320, height: 640 } });
  await scrollPastHero(page);
  const fab = page.locator("#support-fab");
  await fab.waitFor({ state: "visible" });
  const box = await fab.boundingBox();
  assert.ok(box.x >= 0 && box.x + box.width <= 320 && box.y + box.height <= 640);
  assert.ok(box.width <= 170 && box.height <= 56, `${box.width}x${box.height}`);
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  await done();
});

test("the floating button has no motion when reduced motion is asked for", async () => {
  const { page, done } = await openStubbed(site, "/", { reducedMotion: "reduce" });
  await scrollPastHero(page);
  const fab = page.locator("#support-fab");
  await fab.waitFor({ state: "visible" });
  const m = await fab.evaluate((b) => { const s = getComputedStyle(b); return [s.transitionDuration, s.animationName]; });
  assert.deepEqual(m, ["0s", "none"]);
  await done();
});

test("the dialog fits a small screen and scrolls", async () => {
  const { page, done } = await openStubbed(site, "/", { viewport: { width: 320, height: 568 } });
  await page.locator("#hero a[data-download]").click();
  const box = await page.locator("#support-dialog").boundingBox();
  assert.ok(box.x >= 0 && box.x + box.width <= 320 && box.y >= 0 && box.y + box.height <= 568);
  assert.ok(await page.locator("#support-dialog").evaluate((d) => d.scrollHeight > d.clientHeight));
  assert.equal(await page.locator("#kofiframe").evaluate((f) => f.getBoundingClientRect().width <= 320), true);
  await done();
});

for (const [path, viewport] of [["/", { width: 1280, height: 800 }], ["/ru/", { width: 320, height: 568 }]]) {
  test(`${path} keeps the close button in reach at ${viewport.width}`, async () => {
    const { page, done } = await openStubbed(site, path, { viewport });
    await page.locator("#hero a[data-download]").click();
    await page.locator("#kofiframe").waitFor();
    const dialog = page.locator("#support-dialog");
    const close = page.locator("#support-dialog [data-close]");
    const start = await close.boundingBox();
    await dialog.evaluate((d) => { d.scrollTop = d.scrollHeight; });
    assert.ok(await dialog.evaluate((d) => d.scrollTop > 0));
    const box = await close.boundingBox();
    const frame = await dialog.boundingBox();
    assert.ok(Math.abs(box.y - start.y) <= 1, `${start.y} then ${box.y}`);
    assert.ok(box.y >= frame.y && box.x + box.width <= frame.x + frame.width);
    await close.click();
    assert.equal(await dialogOpen(page), false);
    await done();
  });

  test(`${path} does not let the close button cover the dialog's title at ${viewport.width}`, async () => {
    const { page, done } = await openStubbed(site, path, { viewport });
    await page.locator("#hero a[data-download]").click();
    const close = await page.locator("#support-dialog [data-close]").boundingBox();
    const lines = await page.locator('#support-dialog [data-variant="download"] h2').evaluate((h) => {
      const range = document.createRange();
      range.selectNodeContents(h);
      return [...range.getClientRects()].map(({ top, bottom, right }) => ({ top, bottom, right }));
    });
    for (const line of lines) {
      const beside = line.top < close.y + close.height && line.bottom > close.y;
      assert.ok(!beside || line.right <= close.x, `title ends at ${line.right}, button starts at ${close.x}`);
    }
    await done();
  });
}

for (const path of ["/", "/ru/"]) {
  test(`${path} marks the status lamps as an illustration`, async () => {
    const { page, done } = await openStubbed(site, path);
    assert.ok(await page.locator(".card-check .lamps-note").isVisible());
    await done();
  });
}

for (const path of ["/", "/ru/"]) {
  for (const width of [390, 1440]) {
    test(`${path} lines up the real before and after shots at ${width}`, async () => {
      const { page, done } = await open(path, { viewport: { width, height: 900 } });
      assert.equal(await page.locator("#picker .placeholder").count(), 0);
      const shots = page.locator("#picker .pair img");
      assert.equal(await shots.count(), 2);
      await shots.evaluateAll((imgs) => Promise.all(imgs.map((i) => { i.loading = "eager"; return i.decode(); })));
      assert.match(await shots.nth(0).getAttribute("src"), /picker-before\.webp$/);
      // On a phone the picture is zoomed inside its frame, so the frames are what must line up.
      const frames = page.locator("#picker .pair .shot");
      const [before, after] = [await frames.nth(0).boundingBox(), await frames.nth(1).boundingBox()];
      assert.ok(Math.abs(before.width - after.width) <= 1 && Math.abs(before.height - after.height) <= 1);
      assert.ok(before.x >= 0 && before.x + before.width <= width);
      const sizes = await shots.evaluateAll((imgs) => imgs.map((i) => `${i.naturalWidth}x${i.naturalHeight}`));
      assert.equal(sizes[0], sizes[1]);
      await done();
    });
  }
}

for (const [path, copyFile, labels] of [
  ["/", "en", ["Support", "Star on GitHub", "Found a bug?"]],
  ["/ru/", "ru", ["Поддержать", "Звезда на GitHub", "Нашли ошибку?"]],
]) {
  const supportLinks = async (page) => {
    const links = page.locator("#support .support-links a");
    assert.equal(await links.count(), 3);
    await page.locator("#support").scrollIntoViewIfNeeded();
    return Promise.all([0, 1, 2].map((i) => links.nth(i).boundingBox()));
  };

  test(`${path} shows the support buttons as one even row at 1440`, async () => {
    const { page, done } = await open(path, { viewport: { width: 1440, height: 900 } });
    const links = page.locator("#support .support-links a");
    assert.deepEqual((await links.allInnerTexts()).map((t) => t.trim()), labels);
    const boxes = await supportLinks(page);
    for (const b of boxes) {
      assert.ok(Math.abs(b.y - boxes[0].y) <= 0.5, `top ${b.y} vs ${boxes[0].y}`);
      assert.ok(Math.abs(b.height - boxes[0].height) <= 0.5, `height ${b.height} vs ${boxes[0].height}`);
      assert.ok(Math.abs(b.width - boxes[0].width) <= 0.5, `width ${b.width} vs ${boxes[0].width}`);
    }
    assert.equal(await links.locator("svg").count(), 3);
    assert.match(await links.first().evaluate((a) => getComputedStyle(a).backgroundImage), /gradient/);
    await done();
  });

  for (const width of [320, 390]) {
    test(`${path} keeps the support buttons equally wide at ${width}`, async () => {
      const { page, done } = await open(path, { viewport: { width, height: 800 } });
      const boxes = await supportLinks(page);
      for (const b of boxes) {
        assert.ok(Math.abs(b.width - boxes[0].width) <= 0.5, `width ${b.width} vs ${boxes[0].width}`);
        assert.ok(b.x >= 0 && b.x + b.width <= width);
      }
      await done();
    });
  }
}

const near = (a, b, label) => assert.ok(Math.abs(a - b) <= 0.5, `${label}: ${a} vs ${b}`);
const boxesOf = async (locator) => {
  const n = await locator.count();
  return Promise.all(Array.from({ length: n }, (_, i) => locator.nth(i).boundingBox()));
};

for (const [path, copyFile] of [["/", "en"], ["/ru/", "ru"]]) {
  test(`${path} sets the install steps as three even cards over one panel at 1440`, async () => {
    const copy = JSON.parse(await readFile(join(here, `../src/copy/${copyFile}.json`), "utf8"));
    const { page, done } = await open(path, { viewport: { width: 1440, height: 900 } });
    await page.addStyleTag({ content: ".rise { animation: none !important; }" });
    const cards = await boxesOf(page.locator("#install .step"));
    assert.equal(cards.length, 3);
    for (const c of cards) {
      near(c.y, cards[0].y, "top");
      near(c.height, cards[0].height, "height");
      near(c.width, cards[0].width, "width");
    }
    assert.equal(await page.locator("#install .step [data-macos]").count(), 0, "paths live in the panel");
    const panel = await page.locator("#install .paths").boundingBox();
    assert.ok(panel.y >= cards[0].y + cards[0].height, "the panel sits below the cards");
    near(panel.x, cards[0].x, "panel left");
    near(panel.x + panel.width, cards[2].x + cards[2].width, "panel right");
    const paths = await boxesOf(page.locator("#install .paths [data-macos]"));
    assert.equal(paths.length, 2);
    near(paths[0].y, paths[1].y, "path top");
    near(paths[0].height, paths[1].height, "path height");
    near(paths[0].width, paths[1].width, "path width");
    const why = await page.locator("#install .why").boundingBox();
    assert.ok(why.y >= paths[0].y + paths[0].height, "the note follows the paths");
    const text = await page.locator("#install").innerText();
    for (const p of copy.install.steps.flatMap((s) => s.paths ?? [])) {
      assert.ok(text.includes(p.label) && text.includes(p.text), p.label);
    }
    assert.ok(text.includes(copy.install.why));
    await done();
  });

  test(`${path} stacks the install block at full width on a phone`, async () => {
    const { page, done } = await open(path, { viewport: { width: 390, height: 800 } });
    await page.addStyleTag({ content: ".rise { animation: none !important; }" });
    const cards = await boxesOf(page.locator("#install .step"));
    const paths = await boxesOf(page.locator("#install .paths [data-macos]"));
    const panel = await page.locator("#install .paths").boundingBox();
    for (const c of cards) near(c.width, cards[0].width, "card width");
    near(panel.width, cards[0].width, "panel width");
    near(paths[0].width, paths[1].width, "path width");
    assert.ok(cards[1].y > cards[0].y && cards[2].y > cards[1].y && paths[1].y > paths[0].y);
    await done();
  });

  test(`${path} lets the footer text use the footer's width at 1440`, async () => {
    const { page, done } = await open(path, { viewport: { width: 1440, height: 900 } });
    const legal = page.locator("footer .legal");
    const [text, links] = [await legal.boundingBox(), await page.locator("footer .foot-links").boundingBox()];
    near(text.x, links.x, "left");
    near(text.width, links.width, "width");
    const lines = await legal.evaluate((p) => {
      const range = document.createRange();
      range.selectNodeContents(p);
      return new Set([...range.getClientRects()].map((r) => Math.round(r.top))).size;
    });
    assert.ok(lines <= 2, `${lines} lines`);
    await done();
  });
}

test("the Russian headline keeps the accent on the product and the preposition off a line end", async () => {
  for (const width of [320, 390, 1440]) {
    const { page, done } = await open("/ru/", { viewport: { width, height: 800 } });
    const accent = page.locator("h1 [data-gradient]");
    assert.equal((await accent.innerText()).replace(/\s+/g, " ").trim(), "FL Studio на Mac");
    const lines = await page.locator("h1").evaluate((h) => {
      const walker = document.createTreeWalker(h, NodeFilter.SHOW_TEXT);
      const range = document.createRange();
      const found = new Map();
      while (walker.nextNode()) {
        const node = walker.currentNode;
        for (let i = 0; i < node.length; i++) {
          range.setStart(node, i);
          range.setEnd(node, i + 1);
          const rect = range.getClientRects()[0];
          if (!rect) continue;
          const top = Math.round(rect.top);
          found.set(top, (found.get(top) ?? "") + node.data[i]);
        }
      }
      return [...found.values()].map((l) => l.replace(/\s+/g, " ").trim());
    });
    for (const line of lines) assert.ok(!/ в$/.test(line) && line !== "в", `${width}: ${line}`);
    await done();
  }
});

for (const width of [320, 393, 768]) {
  for (const path of ["/", "/ru/"]) {
    test(`${path} shows the whole hero image inside the gutters at ${width}`, async () => {
      const { page, done } = await open(path, { viewport: { width, height: 800 } });
      const image = page.locator(".hero-media img");
      const box = await image.boundingBox();
      assert.ok(box.x >= 15.5, `left ${box.x}`);
      assert.ok(box.x + box.width <= width - 15.5, `right ${box.x + box.width}`);
      assert.ok(Math.abs(box.x - (width - box.x - box.width)) <= 1, "centred");
      const ratio = await image.evaluate((i) => i.naturalWidth / i.naturalHeight);
      assert.ok(Math.abs(box.width / box.height - ratio) <= 0.02, "not cropped");
      await done();
    });
  }
}

for (const path of ["/", "/ru/"]) {
  test(`${path} gives every image in the markup a real alt`, async () => {
    const { page, done } = await open(path);
    const alts = await page.$$eval("img", (imgs) => imgs.map((i) => [i.getAttribute("src"), i.getAttribute("alt")]));
    for (const [src, alt] of alts) assert.ok(alt?.trim(), `${src} has no alt`);
    const icons = alts.filter(([src]) => src.endsWith("icon.png"));
    assert.ok(icons.length >= 2);
    for (const [, alt] of icons) assert.equal(alt, "Plugin Sorter");
    const name = await page.locator("header a.brand").evaluate((a) => a.getAttribute("aria-label"));
    assert.equal(name, "Plugin Sorter", "the logo and its text are read once");
    await done();
  });
}

// ---- The moving strip ----
test("the strip moves on one compositor layer, and nothing heavy sits on it", async () => {
  const { page, done } = await open("/", { viewport: { width: 1440, height: 900 } });
  const info = await page.evaluate(() => {
    const strip = document.querySelector(".strip");
    const inner = document.querySelector(".strip-in");
    const animations = inner.getAnimations();
    return {
      count: animations.length,
      keyframes: animations[0]?.effect.getKeyframes().map((k) => Object.keys(k).filter((n) => !["offset", "computedOffset", "easing", "composite"].includes(n))),
      to: animations[0]?.effect.getKeyframes().at(-1).transform,
      willChange: getComputedStyle(inner).willChange,
      filter: getComputedStyle(inner).filter,
      masks: [strip, inner].map((e) => getComputedStyle(e).maskImage),
      blur: [strip, inner].map((e) => getComputedStyle(e).backdropFilter),
      images: strip.querySelectorAll("img").length,
    };
  });
  assert.equal(info.count, 1);
  for (const props of info.keyframes) assert.deepEqual(props, ["transform"]);
  assert.match(info.to, /translate3d\(-50%/);
  assert.equal(info.willChange, "transform");
  assert.equal(info.filter, "none");
  assert.deepEqual(info.masks, ["none", "none"]);
  assert.deepEqual(info.blur, ["none", "none"]);
  assert.equal(info.images, 0, "one background layer, no duplicated images");
  await done();
});

test("the strip is sharp at 2x and loops without a jump", async () => {
  const { page, done } = await open("/", { viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
  const { natural, cssHeight, width, tile } = await page.evaluate(async () => {
    const inner = document.querySelector(".strip-in");
    const style = getComputedStyle(inner);
    const url = style.backgroundImage.match(/url\("(.+)"\)/)[1];
    const img = new Image();
    img.src = url;
    await img.decode();
    const box = inner.getBoundingClientRect();
    return {
      natural: [img.naturalWidth, img.naturalHeight],
      cssHeight: box.height,
      width: box.width,
      tile: (box.height * img.naturalWidth) / img.naturalHeight,
    };
  });
  assert.ok(natural[1] >= cssHeight * 2 - 0.5, `${natural[1]}px file for ${cssHeight}px at 2x`);
  assert.ok(Math.abs(width / 2 - tile) <= 0.5, `half the layer ${width / 2}, one picture ${tile}`);
  await done();
});

test("the strip pauses off-screen and carries on when it comes back", async () => {
  const { page, done } = await open("/", { viewport: { width: 1440, height: 900 } });
  const state = () => page.locator(".strip-in").evaluate((e) => getComputedStyle(e).animationPlayState);
  await page.evaluate(() => { document.documentElement.style.scrollBehavior = "auto"; });
  await page.evaluate(() => document.querySelector(".strip").scrollIntoView({ block: "center" }));
  await page.waitForFunction(() => getComputedStyle(document.querySelector(".strip-in")).animationPlayState === "running");
  await page.evaluate(() => scrollTo(0, document.body.scrollHeight));
  await page.waitForFunction(() => getComputedStyle(document.querySelector(".strip-in")).animationPlayState === "paused");
  assert.equal(await state(), "paused");
  await page.evaluate(() => document.querySelector(".strip").scrollIntoView({ block: "center" }));
  await page.waitForFunction(() => getComputedStyle(document.querySelector(".strip-in")).animationPlayState === "running");
  await done();
});

test("the strip stands still for reduced motion", async () => {
  const { page, done } = await open("/", { viewport: { width: 1440, height: 900 }, reducedMotion: "reduce" });
  assert.equal(await page.locator(".strip-in").evaluate((e) => e.getAnimations().length), 0);
  await done();
});

test("the hero picture has every pixel of its source at 2x", async () => {
  const { page, done } = await open("/", { viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
  // naturalWidth of a srcset image is corrected for density, so measure the file itself.
  const shown = await page.locator(".hero-media img").evaluate(async (i) => {
    const file = new Image();
    file.src = i.currentSrc;
    await file.decode();
    return [i.currentSrc.split("/").pop(), file.naturalWidth];
  });
  assert.deepEqual(shown, ["app.webp", 1800]);
  await done();
});
