import { mkdir, rm, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import * as esbuild from "esbuild";

const __dirname = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(__dirname, "..");
const outputRoot = resolve(packageRoot, ".cloudbase/functions/generate");

await rm(outputRoot, { force: true, recursive: true });
await mkdir(outputRoot, { recursive: true });

await esbuild.build({
  entryPoints: [resolve(packageRoot, "src/functions/generate/webEntry.js")],
  bundle: true,
  platform: "node",
  target: "node18",
  format: "cjs",
  outfile: resolve(outputRoot, "index.js")
});

await writeFile(
  resolve(outputRoot, "package.json"),
  JSON.stringify({
    name: "beforeshow-generate",
    version: "0.1.0",
    private: true,
    main: "index.js",
    engines: {
      node: ">=18"
    }
  }, null, 2) + "\n"
);

await writeFile(
  resolve(outputRoot, "scf_bootstrap"),
  "#!/bin/bash\nexport PORT=9000\nnode index.js\n"
);

console.log(`Prepared CloudBase function at ${outputRoot}`);
