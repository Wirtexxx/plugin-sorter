import { readFile, writeFile, mkdir, cp, rm, access } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { page, notFoundPage, RELEASE_IMAGES } from "./src/page.mjs";

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

  // Assets are cached for a month, so the stylesheet and script links change with their content
  const sources = await Promise.all(["styles.css", "site.js"].map((f) => readFile(join(here, "src", f))));
  const version = createHash("sha256").update(Buffer.concat(sources)).digest("hex").slice(0, 8);

  await rm(outDir, { recursive: true, force: true });
  for (const p of pages) {
    const copy = JSON.parse(await readFile(join(here, `src/copy/${p.lang}.json`), "utf8"));
    const other = pages.find((o) => o !== p);
    const html = page(copy, { lang: p.lang, config, hasBefore, otherUrl: other.url, url: p.url, version });
    await mkdir(join(outDir, p.dir), { recursive: true });
    await writeFile(join(outDir, p.dir, "index.html"), html);
    // Without a 404 page Cloudflare Pages answers every unknown address with the home page
    await writeFile(join(outDir, p.dir, "404.html"), notFoundPage(copy, { lang: p.lang, home: p.dir ? `/${p.dir}/` : "/", version }));
  }

  if (await exists(assetsDir)) await cp(assetsDir, join(outDir, "assets"), { recursive: true });
  await mkdir(join(outDir, "assets"), { recursive: true });
  await cp(join(here, "src/styles.css"), join(outDir, "assets/styles.css"));
  await cp(join(here, "src/site.js"), join(outDir, "assets/site.js"));

  const urls = pages.map((p) => `  <url><loc>${p.url}</loc></url>`).join("\n");
  await writeFile(join(outDir, "sitemap.xml"),
    `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`);
  await writeFile(join(outDir, "robots.txt"), `User-agent: *\nAllow: /\n\nSitemap: ${origin}/sitemap.xml\n`);
  await cp(join(here, "src/_headers"), join(outDir, "_headers"));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await buildSite({ release: process.argv.includes("--release") });
}
