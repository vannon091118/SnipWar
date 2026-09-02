#!/usr/bin/env node
/*
 * mcp_stresstest.js — Load/queue test for the Godot MCP server over TCP.
 *
 * Fires N tool calls (mix of sync + async) against a running game
 * (`$GODOT_BIN --path . -- --mcp --mcp-port 9090`) and evaluates:
 *   - latency quantiles (p50/p75/p90/p95/p99/max/mean) per phase + overall
 *   - lifecycle queue behavior: async calls are serialized server-side
 *     (async_pending/async_busy from runtime_mcp_status), sync calls stay
 *     responsive while the queue is busy
 *
 * Node only, no dependencies.
 *
 * Usage:
 *   node client/mcp_stresstest.js [--port 9090] [--calls 1000]
 *                                 [--batch 24] [--busy-sync 100]
 */

const net = require("net");

const DEFAULTS = { port: 9090, host: "127.0.0.1", calls: 1000, batch: 24, busySync: 100 };

function parseArgs(argv) {
  const a = { ...DEFAULTS };
  for (let i = 2; i < argv.length; i += 2) {
    const k = argv[i].replace(/^--/, "");
    if (k in a) a[k] = Number(argv[i + 1]);
  }
  return a;
}

class Rpc {
  constructor(host, port) {
    this.sock = net.connect(port, host);
    this.host = host;
    this.port = port;
    this.buf = "";
    this.seq = 0;
    this.pending = new Map();
    this.sock.on("data", (d) => this._onData(d));
  }
  _onData(d) {
    this.buf += d.toString("utf8");
    let idx;
    while ((idx = this.buf.indexOf("\n")) >= 0) {
      const line = this.buf.slice(0, idx).trim();
      this.buf = this.buf.slice(idx + 1);
      if (!line) continue;
      let msg;
      try { msg = JSON.parse(line); } catch { continue; }
      if (msg.id && this.pending.has(msg.id)) {
        const p = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        if (msg.error) p.reject(new Error(JSON.stringify(msg.error)));
        else p.resolve(msg);
      }
    }
  }
  open() {
    return new Promise((res, rej) => {
      this.sock.once("connect", res);
      this.sock.once("error", rej);
    });
  }
  call(method, params) {
    const t0 = performance.now();
    return new Promise((resolve, reject) => {
      const id = ++this.seq;
      this.pending.set(id, { resolve, reject });
      this.sock.write(JSON.stringify({ jsonrpc: "2.0", id, method, params: params || {} }) + "\n");
    }).then((msg) => ({ latencyMs: performance.now() - t0, msg }));
  }
  tool(name, args) {
    return this.call("tools/call", { name, arguments: args || {} }).then(({ latencyMs, msg }) => {
      const result = msg.result || {};
      const text = (result.content || []).find((c) => c.type === "text");
      let data = {};
      if (text) { try { data = JSON.parse(text.text); } catch { data = { raw: text.text }; } }
      return { latencyMs, data, isError: !!result.isError };
    });
  }
}

/* ---- quantiles ---------------------------------------------------------- */
function quantile(sorted, p) {
  if (!sorted.length) return 0;
  const idx = Math.min(sorted.length - 1, Math.max(0, Math.round(p * sorted.length) - 1));
  return sorted[idx];
}
function summarize(samples) {
  if (!samples.length) return { n: 0 };
  const s = [...samples].sort((a, b) => a - b);
  const sum = s.reduce((x, y) => x + y, 0);
  return {
    n: s.length,
    meanMs: +(sum / s.length).toFixed(2),
    p50Ms: +quantile(s, 0.5).toFixed(2),
    p75Ms: +quantile(s, 0.75).toFixed(2),
    p90Ms: +quantile(s, 0.9).toFixed(2),
    p95Ms: +quantile(s, 0.95).toFixed(2),
    p99Ms: +quantile(s, 0.99).toFixed(2),
    maxMs: +s[s.length - 1].toFixed(2),
  };
}

function printTable(rows) {
  const headers = ["phase", "n", "mean", "p50", "p75", "p90", "p95", "p99", "max"];
  const pad = (v, w) => String(v).padStart(w);
  console.log("  " + headers.map((h) => pad(h, headers.indexOf(h) === 0 ? 14 : 8)).join(""));
  for (const r of rows) {
    console.log("  " + [
      r.phase.padEnd(14),
      pad(r.sum.n, 9),
      [r.sum.meanMs, r.sum.p50Ms, r.sum.p75Ms, r.sum.p90Ms, r.sum.p95Ms, r.sum.p99Ms, r.sum.maxMs]
        .map((v) => pad(v.toFixed(1), 9)).join(""),
    ].join(""));
  }
}

/* ---- tool pools ---------------------------------------------------------------*/
const SYNC_POOL = [
  ["runtime_ux_scan", {}],
  ["runtime_get_scene_tree", { max_depth: 2 }],
  ["runtime_engine_info", {}],
  ["runtime_perf_metrics", {}],
  ["runtime_ux_snapshot", {}],
];

// Screenshot capture is intentionally excluded from the latency stress run;
// pure wait_ms flavors prove the async path + queue without image work.
const ASYNC_POOL = [
  ["runtime_wait_ms", { ms: 20 }],
  ["runtime_wait_ms", { ms: 50 }],
  ["runtime_wait_ms", { ms: 100 }],
];

function pick(pool, i) {
  return pool[i % pool.length];
}

async function main() {
  const a = parseArgs(process.argv);
  const rpc = new Rpc(a.host, a.port);
  await rpc.open();
  await rpc.call("initialize", { protocolVersion: "2024-11-05" });
  await rpc.call("initialized", {});

  console.log(`MCP stresstest: ${a.calls} sync-calls, config: host=${a.host} port=${a.port}\n`);

  // ---- Phase A: sequential sync baseline ----
  console.log("[1/3] sync baseline (" + a.calls + " calls)…");
  const syncSamples = [];
  for (let i = 0; i < a.calls; i++) {
    const [name, args] = pick(SYNC_POOL, i);
    const r = await rpc.tool(name, args);
    syncSamples.push(r.latencyMs);
    if (r.isError) console.error(`  ERROR on ${name}: ${JSON.stringify(r.data)}`);
  }

  // ---- Phase B: concurrent async (queue behavior) ----
  console.log("[2/3] queue flood (" + a.batch + " concurrent async)…");
  const queueSamples = [];
  const pendingSeen = [];
  const statusTimer = setInterval(async () => {
    try {
      const s = await rpc.tool("runtime_mcp_status", {});
      pendingSeen.push((typeof s.async_pending === "number" ? s.async_pending : 0) + (s.async_busy ? 1 : 0));
    } catch { /* ignore */ }
  }, 100);

  const t0 = performance.now();
  const queuePromises = [];
  for (let i = 0; i < a.batch; i++) {
    const [name, args] = pick(ASYNC_POOL, i);
    queuePromises.push(rpc.tool(name, args));
  }
  const settled = await Promise.allSettled(queuePromises);
  const queueWallMs = performance.now() - t0;
  clearInterval(statusTimer);
  for (const p of settled) {
    queueSamples.push(p.status === "fulfilled" ? p.value.latencyMs : -1);
    if (p.status === "rejected") console.error(`  ERROR async: ${p.reason && p.reason.message}`);
  }

  // ---- Phase C: sync during busy queue (responsiveness while async pending) ----
  console.log("[3/3] sync-during-busy (" + a.busySync + " calls while " + Math.min(a.batch, 8) + " async in flight)…");
  const busyAsync = [];
  for (let i = 0; i < Math.min(8, a.batch); i++) {
    const [name, args] = pick(ASYNC_POOL, i + 3);
    busyAsync.push(rpc.tool(name, args));
  }
  const busySyncSamples = [];
  for (let i = 0; i < a.busySync; i++) {
    const [name, args] = pick(SYNC_POOL, i);
    const r = await rpc.tool(name, args);
    busySyncSamples.push(r.latencyMs);
  }
  await Promise.allSettled(busyAsync);

  // ---- report ----
  const tables = [
    { phase: "sync", sum: summarize(syncSamples) },
    { phase: "async(queue)", sum: summarize(queueSamples) },
    { phase: "sync while busy", sum: summarize(busySyncSamples) },
    { phase: "overall", sum: summarize([...syncSamples, ...queueSamples, ...busySyncSamples]) },
  ];
  console.log("\nLatency quantiles (ms):");
  printTable(tables);

  const expectedSerial = queueSamples.reduce((s, x) => s + Math.max(0, x), 0);
  console.log("\nQueue behavior:");
  console.log(`  async batch: ${queueSamples.length} calls | wall=${queueWallMs.toFixed(0)}ms | sum-of-latencies=${expectedSerial.toFixed(0)}ms`);
  console.log(`  serialization ratio (sum/wall): ${(expectedSerial / Math.max(1, queueWallMs)).toFixed(2)} (≈1 = fully serialized server-side)`);
  if (pendingSeen.length) {
    console.log(`  async_pending samples: max=${Math.max(...pendingSeen)} avg=${(pendingSeen.reduce((s, x) => s + x, 0) / pendingSeen.length).toFixed(1)} over ${pendingSeen.length} polls`);
  }

  // verdict
  const all = [...syncSamples, ...queueSamples, ...busySyncSamples];
  const errors = all.filter((x) => x < 0).length;
  const bad = errors > 0 || summarize(all).maxMs > 5000;
  console.log(`\nVERDICT: ${bad ? "FAIL" : "PASS"} | total calls=${all.length} errors=${errors}`);
  process.exit(bad ? 1 : 0);
}

main().catch((e) => {
  console.error("STRESSTEST_ERROR:", e.message);
  process.exit(2);
});