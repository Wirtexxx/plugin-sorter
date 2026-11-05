import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { buildSite } from "../build.mjs";
import { serveDir } from "../scripts/serve.mjs";

const here = dirname(fileURLToPath(import.meta.url));

/** Builds the site into a temp folder with `config` over site.config.json and serves it. */
export async function serveBuild({ config = {} } = {}) {
  const base = JSON.parse(await readFile(join(here, "../site.config.json"), "utf8"));
  const outDir = await mkdtemp(join(tmpdir(), "ps-serve-"));
  await buildSite({ outDir, config: { ...base, ...config } });
  const server = await serveDir(outDir);
  return {
    url: server.url,
    close: async () => {
      await server.close();
      await rm(outDir, { recursive: true, force: true });
    },
  };
}
