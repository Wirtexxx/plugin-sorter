import { readFile, writeFile, mkdir, cp, rm, access } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { page, RELEASE_IMAGES } from "./src/page.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const exists = (p) => access(p).then(() => true, () => false);

export async function buildSite({
  release = false,
  outDir = join(here, "dist"),
  config,
  assetsDir = join(here, "assets"),
} = {}) {
  config ??= JSON.parse(await readFile(join(here, "site.config.json"), "utf8"));
  const hasBefore = await exists(join(assetsDir, "picker-before.webp"));
  if (release) {
    for (const name of RELEASE_IMAGES) {
      if (!(await exists(join(assetsDir, name)))) throw new Error(`Missing ${name}`);
    }
  }

  const origin = `https://${config.domain}`;
  const pages = [
    { lang: "en", dir: "", url: `${origin}/` },
    { lang: "ru", dir: "ru", url: `${origin}/ru/` },
  ];

  await rm(outDir, { recursive: true, force: true });
  for (const p of pages) {
    const copy = JSON.parse(await readFile(join(here, `src/copy/${p.lang}.json`), "utf8"));
    const other = pages.find((o) => o !== p);
    const html = page(copy, { lang: p.lang, config, hasBefore, otherUrl: other.url, url: p.url });
    await mkdir(join(outDir, p.dir), { recursive: true });
    await writeFile(join(outDir, p.dir, "index.html"), html);
  }

  if (await exists(assetsDir)) await cp(assetsDir, join(outDir, "assets"), { recursive: true });
  await mkdir(join(outDir, "assets"), { recursive: true });
  await cp(join(here, "src/styles.css"), join(outDir, "assets/styles.css"));
  await cp(join(here, "src/site.js"), join(outDir, "assets/site.js"));

  const urls = pages.map((p) => `  <url><loc>${p.url}</loc></url>`).join("\n");
  await writeFile(join(outDir, "sitemap.xml"),
    `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`);
  await writeFile(join(outDir, "robots.txt"), `User-agent: *\nAllow: /\n\nSitemap: ${origin}/sitemap.xml\n`);
  await writeFile(join(outDir, "CNAME"), `${config.domain}\n`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await buildSite({ release: process.argv.includes("--release") });
}
