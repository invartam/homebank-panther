import { createHash } from "node:crypto";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const build = path.join(root, "build");
const cache = process.argv.length === 4 && process.argv[2] === "--downloads"
  ? path.resolve(process.argv[3]) : path.join(build, "https-downloads");
if (process.argv.length !== 2 && !(process.argv.length === 4 && process.argv[2] === "--downloads")) {
  throw new Error("Usage: node scripts/prepare-drive-https.mjs [--downloads dossier]");
}
mkdirSync(build, { recursive: true }); mkdirSync(cache, { recursive: true });
const manifest = JSON.parse(readFileSync(path.join(root, "scripts/https-sources.json"), "utf8"));
const stage = mkdtempSync(path.join(build, "https-kit-"));
try {
  const kit = path.join(stage, "homebank-https-sources"); mkdirSync(kit);
  for (const file of manifest.files) {
    if (!/^[a-zA-Z0-9.-]+$/.test(file.name) || !/^[a-f0-9]{64}$/.test(file.sha256) || new URL(file.url).protocol !== "https:") throw new Error("Manifest HTTPS invalide.");
    const archive = path.join(cache, file.name);
    if (!existsSync(archive)) {
      console.log(`Telechargement officiel : ${file.name}`);
      const temp = path.join(stage, file.name);
      execFileSync("curl", ["-q", "--fail", "--location", "--proto", "=https", "--proto-redir", "=https", "--tlsv1.2",
        "--connect-timeout", "15", "--max-time", "180", "--silent", "--show-error", "--output", temp, file.url], { stdio: "inherit" });
      const hash = createHash("sha256").update(readFileSync(temp)).digest("hex");
      if (hash !== file.sha256) throw new Error(`SHA-256 inattendu pour ${file.name}. Ne pas ignorer cette erreur ni modifier automatiquement le manifeste.`);
      cpSync(temp, archive);
    }
    const hash = createHash("sha256").update(readFileSync(archive)).digest("hex");
    if (hash !== file.sha256) throw new Error(`Cache non conforme pour ${file.name}.`);
    cpSync(archive, path.join(kit, file.name));
    console.log(`SHA-256 verifie : ${file.name}`);
  }
  cpSync(path.join(root, "scripts/build-drive-https.sh"), path.join(kit, "build.sh"));
  cpSync(path.join(root, "scripts/check-drive-https.sh"), path.join(kit, "check-drive-https.sh"));
  cpSync(path.join(root, "scripts/check-architecture.sh"), path.join(kit, "check-architecture.sh"));
  cpSync(path.join(root, "scripts/check-curl-timeval.c"), path.join(kit, "check-curl-timeval.c"));
  cpSync(path.join(root, "scripts/https-sources.json"), path.join(kit, "https-sources.json"));
  cpSync(path.join(root, "HTTPS_BUILD.md"), path.join(kit, "README.md"));
  const output = path.join(build, "HomeBankPanther-https-sources.tar.gz");
  execFileSync("tar", ["-czf", output, "-C", stage, "homebank-https-sources"]);
  writeFileSync(`${output}.sha256`, createHash("sha256").update(readFileSync(output)).digest("hex") + "  " + path.basename(output) + "\n");
  console.log(`Kit de sources prepare : ${output}`);
  console.log("Aucun binaire PPC n'a ete genere. Compilation et HTTPS restent a valider dans Panther.");
} finally { rmSync(stage, { recursive: true, force: true }); }
