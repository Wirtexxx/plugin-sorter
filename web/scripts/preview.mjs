import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { buildSite } from "../build.mjs";
import { serveDir } from "./serve.mjs";

const dist = join(dirname(fileURLToPath(import.meta.url)), "../dist");
await buildSite({ outDir: dist });
const { url } = await serveDir(dist, 4173);
console.log(`Preview: ${url}/ and ${url}/ru/`);
