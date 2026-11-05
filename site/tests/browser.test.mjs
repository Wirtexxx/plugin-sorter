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
    title: "Plugin Sorter: free FL Studio plugin manager for Mac" },
  { path: "/ru/", lang: "ru", h1: "Менеджер плагинов, которого не хватало FL Studio на Mac",
    title: "Plugin Sorter: бесплатный менеджер плагинов FL Studio для Mac" },
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
  await page.evaluate(() => document.querySelector("dialog").showModal());
  const box = await page.locator("dialog").boundingBox();
  assert.ok(box.x >= 0 && box.x + box.width <= 390);
  assert.notEqual(await page.locator("dialog").evaluate((d) => getComputedStyle(d).backgroundColor), "rgb(255, 255, 255)");
});
