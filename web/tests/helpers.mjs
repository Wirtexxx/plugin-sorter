import { createServer } from "node:http";
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

const listen = (handler) => new Promise((resolve, reject) => {
  const server = createServer(handler);
  server.once("error", reject);
  server.listen(0, "127.0.0.1", () => resolve({
    url: `http://127.0.0.1:${server.address().port}`,
    close: () => new Promise((done) => {
      server.closeAllConnections();
      server.close(done);
    }),
  }));
});
const wait = (ms) => new Promise((done) => setTimeout(done, ms));

/**
 * A release download as GitHub serves it: a 302 on one origin, then an attachment on another.
 * Only a real response like this makes Firefox and WebKit stop the page's loads; page.route does not.
 */
export async function serveAttachment({ redirectDelay = 0, fileDelay = 0 } = {}) {
  const file = await listen(async (req, res) => {
    await wait(fileDelay);
    res.writeHead(200, {
      "content-type": "application/octet-stream",
      "content-disposition": 'attachment; filename="PluginSorter.dmg"',
    });
    res.end("dmg");
  });
  const redirect = await listen(async (req, res) => {
    await wait(redirectDelay);
    res.writeHead(302, { location: `${file.url}/PluginSorter.dmg` }).end();
  });
  return {
    url: `${redirect.url}/releases/latest/download/PluginSorter.dmg`,
    close: () => Promise.all([redirect.close(), file.close()]),
  };
}

/** A stand-in for the Ko-fi form on its own origin. The first `hang` requests never get an answer. */
export async function serveForm({ delay = 300, hang = 0 } = {}) {
  let requests = 0;
  const server = await listen(async (req, res) => {
    if (req.url.startsWith("/favicon")) return res.writeHead(404).end();
    if (++requests <= hang) return;
    await wait(delay);
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    res.end("<!doctype html><title>stub</title><h1>Ko-fi form (stub)</h1>");
  });
  return { ...server, requests: () => requests };
}
