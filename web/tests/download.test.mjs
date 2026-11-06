// The Ko-fi form next to a real download, in every engine. Firefox and WebKit stop a page's
// in-flight loads when a link navigates, even if the response then turns out to be an attachment.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { chromium, firefox, webkit } from "playwright";
import { serveBuild, serveAttachment, serveForm } from "./helpers.mjs";

const ENGINES = { chromium, firefox, webkit };
const FORM_TEXT = "Ko-fi form (stub)";
const browsers = {};

before(async () => {
  const site = await serveBuild();
  for (const [name, engine] of Object.entries(ENGINES)) {
    browsers[name] = await engine.launch();
    // On a fresh machine, like CI, WebKit needs about 3 s for its first frames of this page, and a
    // click waits for frames. Pay for them here, not out of the 5 s a test gives its first click.
    const page = await browsers[name].newPage();
    await page.goto(site.url, { waitUntil: "load" });
    await page.evaluate(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))));
    await page.close();
  }
  await site.close();
});
after(() => Promise.all(Object.values(browsers).map((b) => b.close())));

/** Serves the site against a local attachment and form server, and opens it. */
async function setup(t, engine, { attachment = {}, form = {} } = {}) {
  const file = await serveAttachment(attachment);
  const kofi = await serveForm(form);
  const site = await serveBuild({ config: { downloadUrl: file.url, koFiEmbedUrl: `${kofi.url}/wirtex/` } });
  const context = await browsers[engine].newContext({ viewport: { width: 1280, height: 800 } });
  t.after(async () => {
    await context.close();
    await Promise.all([site.close(), kofi.close(), file.close()]);
  });
  const page = await context.newPage();
  page.setDefaultTimeout(5000);
  await page.goto(site.url, { waitUntil: "load" });
  return { page, site, kofi };
}

const formShows = (page) => page.frameLocator("#kofiframe").getByText(FORM_TEXT).waitFor({ timeout: 4000 });

for (const engine of Object.keys(ENGINES)) {
  for (const [name, attachment] of Object.entries({
    "a fast server": {},
    "a slow redirect": { redirectDelay: 1500 },
    "a slow file": { fileDelay: 1500 },
  })) {
    test(`${engine}: the form loads after a download from ${name}`, async (t) => {
      const { page, site } = await setup(t, engine, { attachment });
      const download = page.waitForEvent("download");
      await page.locator("#hero a[data-download]").click();
      assert.equal((await download).suggestedFilename(), "PluginSorter.dmg");
      await formShows(page);
      assert.equal(page.url(), `${site.url}/`);
      assert.equal(await page.locator("#support-dialog").evaluate((d) => d.open), true);
    });
  }

  test(`${engine}: the download starts at once, not after the form`, async (t) => {
    const { page } = await setup(t, engine, { form: { delay: 3000 } });
    const started = Date.now();
    const download = page.waitForEvent("download");
    await page.locator("#hero a[data-download]").click();
    await download;
    assert.ok(Date.now() - started < 1500, `${Date.now() - started} ms`);
  });

  test(`${engine}: a form still loading when the download starts comes back`, async (t) => {
    const { page } = await setup(t, engine, { form: { delay: 1000 } });
    await page.locator("#support-fab").evaluate((b) => b.click());
    await page.locator("#kofiframe").waitFor();
    await page.keyboard.press("Escape");
    const download = page.waitForEvent("download");
    await page.locator("#hero a[data-download]").click();
    await download;
    await formShows(page);
    assert.equal(await page.locator("iframe").count(), 1);
  });

  test(`${engine}: reopening brings back a form that never loaded`, async (t) => {
    const { page, kofi } = await setup(t, engine, { form: { hang: 1 } });
    const link = page.locator("#hero a[data-download]");
    await link.click();
    await page.locator("#kofiframe").waitFor();
    await page.keyboard.press("Escape");
    await link.click();
    await formShows(page);
    assert.equal(await page.locator("iframe").count(), 1);
    assert.equal(kofi.requests(), 2);
  });
}
