// Lighthouse quality gate: both pages, mobile and desktop, every category at 90 or more.
import lighthouse, { desktopConfig } from "lighthouse";
import { launch } from "chrome-launcher";
import { chromium } from "playwright";
import { serveBuild } from "./helpers.mjs";

const MIN = 90;
const CATEGORIES = ["performance", "accessibility", "best-practices", "seo"];
const PAGES = ["/", "/ru/"];
const PROFILES = ["mobile", "desktop"];

const site = await serveBuild();
const chrome = await launch({
  chromePath: chromium.executablePath(),
  chromeFlags: ["--headless=new", "--no-sandbox"],
});

const rows = [];
const notes = [];
try {
  for (const path of PAGES) {
    for (const profile of PROFILES) {
      const { lhr } = await lighthouse(
        site.url + path,
        { port: chrome.port, output: "json", logLevel: "error", onlyCategories: CATEGORIES },
        profile === "desktop" ? desktopConfig : undefined,
      );
      const scores = Object.fromEntries(CATEGORIES.map((c) => [c, Math.round((lhr.categories[c].score ?? 0) * 100)]));
      rows.push({ page: path, profile, ...scores });
      for (const c of CATEGORIES) {
        for (const ref of lhr.categories[c].auditRefs) {
          const a = lhr.audits[ref.id];
          if (a.score === null || a.score >= 1 || ref.weight === 0) continue;
          notes.push(`${path} ${profile} ${c}: ${a.id} (${a.score}) ${a.displayValue ?? ""}`.trim());
          for (const item of a.details?.items ?? []) {
            if (item.node && a.score === 0) notes.push(`    ${item.node.snippet?.slice(0, 90)} | ${(item.node.explanation ?? "").split("\n").slice(1).join(" ").slice(0, 160)}`);
          }
        }
      }
    }
  }
} finally {
  await chrome.kill();
  await site.close();
}

console.table(rows);
if (notes.length) console.log("Audits below full marks:\n  " + notes.join("\n  "));
const failing = rows.flatMap((r) => CATEGORIES.filter((c) => r[c] < MIN).map((c) => `${r.page} ${r.profile} ${c}=${r[c]}`));
if (failing.length) {
  console.error(`Below ${MIN}: ${failing.join(", ")}`);
  process.exit(1);
}
console.log(`All scores are ${MIN} or more.`);
