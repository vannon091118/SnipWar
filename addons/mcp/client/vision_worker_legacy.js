#!/usr/bin/env node
/*
 * Local MCP vision worker.
 * Reads PNG artifacts from one session-specific context directory and serves
 * compact JSON jobs over localhost. Image bytes never cross the MCP socket.
 *
 * OCR uses Tesseract.js (bundled via `npm install tesseract.js`). The worker
 * auto-loads the module if present; otherwise OCR falls back to unavailable.
 */

"use strict";

const fs = require("fs");
const net = require("net");
const path = require("path");
const zlib = require("zlib");

let TesseractWorker = null;
try {
  TesseractWorker = require("tesseract.js").createWorker;
} catch (_) {
  // tesseract.js is optional — OCR will report unavailable if missing.
}

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function parseArgs(argv) {
  const result = {
    serve: false,
    host: "127.0.0.1",
    port: 9127,
    contextRoot: ".",
  };
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--serve") result.serve = true;
    else if (arg === "--host") result.host = argv[++i] || result.host;
    else if (arg === "--port") result.port = Number(argv[++i]) || result.port;
    else if (arg === "--context-root") result.contextRoot = argv[++i] || result.contextRoot;
  }
  return result;
}

function safeContextId(value) {
  const id = String(value || "");
  if (!/^[A-Za-z0-9_-]+$/.test(id)) throw new Error("Invalid context id");
  return id;
}

function artifactFromContext(rootValue, contextId) {
  const root = path.resolve(rootValue);
  const id = safeContextId(contextId);
  // Metadaten koennen im Root ODER in Session-Unterordnern liegen
  // (z.B. runtime_runtime_<pid>/ — Context-Store gruppiert pro Session).
  let metadataPath = path.join(root, `${id}.json`);
  if (!fs.existsSync(metadataPath)) {
    const subdirs = fs.readdirSync(root, { withFileTypes: true })
      .filter((e) => e.isDirectory())
      .map((e) => e.name);
    for (const dir of subdirs) {
      const candidate = path.join(root, dir, `${id}.json`);
      if (fs.existsSync(candidate)) {
        metadataPath = candidate;
        break;
      }
    }
  }
  const metadata = JSON.parse(fs.readFileSync(metadataPath, "utf8"));
  const extension = path.extname(String(metadata.worker_path || metadata.path || ".png")).toLowerCase() || ".png";
  if (![".png", ".jpg", ".jpeg"].includes(extension)) {
    throw new Error("Unsupported artifact format");
  }
  const artifactDir = path.dirname(metadataPath);
  const artifact = path.resolve(artifactDir, `${id}${extension}`);
  if (!artifact.startsWith(`${root}${path.sep}`)) {
    throw new Error("Artifact escaped context root");
  }
  if (!fs.statSync(artifact).isFile()) throw new Error("Context image not found");
  return artifact;
}

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}

function decodePng(filePath) {
  const data = fs.readFileSync(filePath);
  if (!data.subarray(0, 8).equals(PNG_SIGNATURE)) throw new Error("Not a PNG file");
  let offset = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  const idat = [];
  while (offset + 12 <= data.length) {
    const length = data.readUInt32BE(offset);
    const type = data.subarray(offset + 4, offset + 8).toString("ascii");
    const chunk = data.subarray(offset + 8, offset + 8 + length);
    if (type === "IHDR") {
      width = chunk.readUInt32BE(0);
      height = chunk.readUInt32BE(4);
      bitDepth = chunk[8];
      colorType = chunk[9];
    } else if (type === "IDAT") {
      idat.push(chunk);
    } else if (type === "IEND") {
      break;
    }
    offset += length + 12;
  }
  if (!width || !height) throw new Error("PNG dimensions unavailable");
  if (bitDepth !== 8 || ![2, 6].includes(colorType)) {
    throw new Error("Only 8-bit RGB/RGBA PNGs are supported");
  }
  const channels = colorType === 6 ? 4 : 3;
  const stride = width * channels;
  const inflated = zlib.inflateSync(Buffer.concat(idat));
  const pixels = Buffer.alloc(width * height * 4);
  let previous = Buffer.alloc(stride);
  let sourceOffset = 0;
  for (let y = 0; y < height; y += 1) {
    const filter = inflated[sourceOffset++];
    const row = Buffer.from(inflated.subarray(sourceOffset, sourceOffset + stride));
    sourceOffset += stride;
    if (row.length !== stride) throw new Error("Invalid PNG scanline");
    for (let i = 0; i < stride; i += 1) {
      const left = i >= channels ? row[i - channels] : 0;
      const up = previous[i] || 0;
      const upLeft = i >= channels ? previous[i - channels] || 0 : 0;
      if (filter === 1) row[i] = (row[i] + left) & 0xff;
      else if (filter === 2) row[i] = (row[i] + up) & 0xff;
      else if (filter === 3) row[i] = (row[i] + Math.floor((left + up) / 2)) & 0xff;
      else if (filter === 4) row[i] = (row[i] + paeth(left, up, upLeft)) & 0xff;
      else if (filter !== 0) throw new Error(`Unsupported PNG filter ${filter}`);
    }
    for (let x = 0; x < width; x += 1) {
      const source = x * channels;
      const target = (y * width + x) * 4;
      pixels[target] = row[source];
      pixels[target + 1] = row[source + 1];
      pixels[target + 2] = row[source + 2];
      pixels[target + 3] = channels === 4 ? row[source + 3] : 255;
    }
    previous = row;
  }
  return { width, height, pixels };
}

function pixel(image, x, y) {
  const index = (y * image.width + x) * 4;
  return [image.pixels[index], image.pixels[index + 1], image.pixels[index + 2], image.pixels[index + 3]];
}

function palette(image, limit = 8) {
  const counts = new Map();
  const step = Math.max(1, Math.floor(Math.min(image.width, image.height) / 24));
  for (let y = 0; y < image.height; y += step) {
    for (let x = 0; x < image.width; x += step) {
      const [r, g, b] = pixel(image, x, y);
      const key = `#${r.toString(16).padStart(2, "0")}${g.toString(16).padStart(2, "0")}${b.toString(16).padStart(2, "0")}`;
      counts.set(key, (counts.get(key) || 0) + 1);
    }
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, limit).map(([key]) => key);
}

function detectRects(image) {
  const rects = [];
  const rowStep = Math.max(1, Math.floor(image.height / 20));
  for (let y = 0; y < image.height; y += rowStep) {
    let previousLum = -1;
    let start = 0;
    for (let x = 1; x < image.width; x += 4) {
      const [r, g, b] = pixel(image, x, y);
      const lum = (r + g + b) / (3 * 255);
      if (previousLum >= 0 && Math.abs(lum - previousLum) > 0.15) {
        if (start) {
          const width = x - start;
          if (width >= 40 && width <= 600) rects.push({ x: start, y, w: width, h: rowStep });
          start = 0;
        } else {
          start = x;
        }
      }
      previousLum = lum;
    }
  }
  return rects.slice(0, 128);
}

function compareImages(first, second) {
  if (first.width !== second.width || first.height !== second.height) {
    return { size_mismatch: true, first: [first.width, first.height], second: [second.width, second.height] };
  }
  const step = Math.max(1, Math.floor(Math.min(first.width, first.height) / 480));
  let changed = 0;
  let sampled = 0;
  for (let y = 0; y < first.height; y += step) {
    for (let x = 0; x < first.width; x += step) {
      const a = pixel(first, x, y);
      const b = pixel(second, x, y);
      sampled += 1;
      if (Math.max(Math.abs(a[0] - b[0]), Math.abs(a[1] - b[1]), Math.abs(a[2] - b[2])) > 5) changed += 1;
    }
  }
  return {
    changed_pixels: changed,
    sampled_pixels: sampled,
    change_ratio: sampled ? changed / sampled : 0,
    stable: changed === 0,
  };
}

function analyzeArtifact(filePath) {
  const image = decodePng(filePath);
  return {
    width: image.width,
    height: image.height,
    palette: palette(image),
    rects: detectRects(image),
    artifact: filePath,
  };
}

// ─── OCR via Tesseract.js (Pool + Asset-Cache) ───────────────────
// Parallelisierung: OCR_POOL_SIZE Tesseract-Worker (default 2, env MCP_OCR_POOL),
// Jobs werden round-robin verteilt und im Serve-Loop NICHT seriell awaited.
// Cache: worker/core werden aus node_modules geladen; heruntergeladene Assets
// (traineddata etc.) landen per cacheMethod "write" in node_modules/.cache
// (innerhalb node_modules -> von .gitignore abgedeckt) und sind beim naechsten
// Worker-Start sofort da, ohne CDN-Roundtrip.

let _ocrPool = [];
let _ocrRoundRobin = 0;
const OCR_POOL_SIZE = Math.max(1, parseInt(process.env.MCP_OCR_POOL || "2", 10) || 2);
const OCR_CACHE_DIR = path.join(__dirname, "node_modules", ".cache", "tesseract.js");
const OCR_OPTIONS = {
  // KEIN workerPath: die Browser-Variante (dist/worker.min.js) braucht
  // addEventListener und crasht in Node. Ohne workerPath waehlt tesseract.js
  // automatisch die Node-kompatible Worker-Variante.
  corePath: path.join(__dirname, "node_modules", "tesseract.js-core"),
  // langPath lokal: deu.traineddata.gz liegt einmalig im Cache-Ordner
  // (siehe Setup-Hinweis) -> Kaltstart ohne CDN-Roundtrip.
  langPath: OCR_CACHE_DIR,
  cacheMethod: "write",
  cachePath: OCR_CACHE_DIR,
};

async function ensureOcrPool() {
  if (_ocrPool.length > 0) return;
  if (!TesseractWorker) throw new Error("tesseract.js is not installed (run: npm install tesseract.js)");
  // Seriell initialisieren: Der erste Worker laedt die Assets (CDN beim
  // Kaltstart), weitere Worker nutzen den tesseract.js-Asset-Cache
  // (cacheMethod "write" -> cachePath) und starten so deutlich schneller.
  for (let i = 0; i < OCR_POOL_SIZE; i++) {
    _ocrPool.push(await TesseractWorker("deu", 1, OCR_OPTIONS));
  }
}

function pickOcrWorker() {
  const worker = _ocrPool[_ocrRoundRobin % _ocrPool.length];
  _ocrRoundRobin = (_ocrRoundRobin + 1) % _ocrPool.length;
  return worker;
}

async function runOcr(job, contextRoot) {
  const id = String(job.id || "");
  if (!TesseractWorker) {
    return { ok: true, id, ocr: { available: false, text: "", reason: "tesseract.js is not installed — run: npm install tesseract.js" } };
  }
  try {
    const artifact = artifactFromContext(contextRoot, job.context_id);
    await ensureOcrPool();
    const worker = pickOcrWorker();
    const { data: { text, confidence } } = await worker.recognize(artifact);
    const lines = text.split("\n").map((l) => l.trim()).filter(Boolean);
    return {
      ok: true, id,
      ocr: {
        available: true,
        text: text.trim(),
        lines,
        confidence: Math.round(confidence),
      },
    };
  } catch (error) {
    return { ok: false, id, ocr: { available: false, text: "", reason: String(error.message || error) } };
  }
}

// ─── Job dispatch ───────────────────────────────────────────────

function handleJob(job, contextRoot) {
  const operation = String(job.operation || "");
  try {
    if (operation === "info") return { ok: true, worker: "vision_worker_node", operations: ["analyze", "ocr", "compare", "info"] };
    if (operation === "analyze") {
      const artifact = artifactFromContext(contextRoot, job.context_id);
      return { ok: true, id: String(job.id || ""), ...analyzeArtifact(artifact) };
    }
    if (operation === "ocr") {
      // Returns a Promise — caller must await.
      return runOcr(job, contextRoot);
    }
    if (operation === "compare") {
      const first = decodePng(artifactFromContext(contextRoot, job.context_a));
      const second = decodePng(artifactFromContext(contextRoot, job.context_b));
      return { ok: true, id: String(job.id || ""), ...compareImages(first, second) };
    }
    return { ok: false, id: String(job.id || ""), error: `Unknown operation: ${operation}` };
  } catch (error) {
    return { ok: false, id: String(job.id || ""), error: String(error.message || error) };
  }
}

// ─── TCP serve loop (async-aware for OCR) ───────────────────────

function serve(options) {
  const contextRoot = path.resolve(options.contextRoot);
  fs.mkdirSync(contextRoot, { recursive: true });
  const server = net.createServer((socket) => {
    let buffer = "";
    socket.setEncoding("utf8");
    socket.on("data", async (chunk) => {
      buffer += chunk;
      if (buffer.length > 1024 * 1024) {
        socket.destroy(new Error("worker request buffer exceeded limit"));
        return;
      }
      let newline;
      while ((newline = buffer.indexOf(String.fromCharCode(10))) >= 0) {
        const line = buffer.slice(0, newline).trim();
        buffer = buffer.slice(newline + 1);
        if (!line) continue;
        try {
          const parsed = JSON.parse(line);
          const isOcrJob = parsed.operation === "ocr" || (parsed.operation === "analyze" && parsed.ocr === true);
          const pending = handleJob(parsed, contextRoot);
          if (pending && typeof pending.then === "function") {
            if (isOcrJob) {
              // OCR-Jobs NICHT seriell awaiten: Antwort schreiben, sobald sie fertig
              // ist (id-basiertes Protokoll, Reihenfolge egal) -> paralleler Durchsatz.
              pending
                .then((res) => socket.write(JSON.stringify(res) + String.fromCharCode(10)))
                .catch((err) => socket.write(JSON.stringify({ ok: false, error: String((err && err.message) || err) }) + String.fromCharCode(10)));
              continue;
            }
            const response = await pending;
            socket.write(JSON.stringify(response) + String.fromCharCode(10));
            continue;
          }
          socket.write(JSON.stringify(pending) + String.fromCharCode(10));
        } catch (error) {
          socket.write(JSON.stringify({ ok: false, error: String((error && error.message) || error) }) + String.fromCharCode(10));
        }
      }
    });
  });
  server.listen(options.port, options.host, () => {
    process.stderr.write(`[vision-worker-node] listening on ${options.host}:${options.port}\n`);
  });
}

const options = parseArgs(process.argv);
if (options.serve) serve(options);
else {
  process.stderr.write("Usage: vision_worker.js --serve --context-root <path> --port <port>\n");
  process.exitCode = 1;
}