const net = require("net");
const fs = require("fs");
const path = require("path");

const HOST = "127.0.0.1";
const PORT = 9090;

class McpClient {
    constructor(host, port) {
        this.host = host; this.port = port;
        this.buf = ""; this.seq = 0; this.pending = new Map(); this.sock = null;
    }
    connect() {
        return new Promise((resolve, reject) => {
            this.sock = net.connect(this.port, this.host);
            this.sock.on("connect", () => {
                this.sock.on("data", (d) => this._onData(d));
                this.sock.on("error", reject);
                resolve();
            });
            this.sock.on("error", reject);
            setTimeout(() => reject(new Error("timeout")), 5000);
        });
    }
    _onData(d) {
        this.buf += d.toString("utf8");
        let idx;
        while ((idx = this.buf.indexOf("\n")) >= 0) {
            const line = this.buf.slice(0, idx).trim();
            this.buf = this.buf.slice(idx + 1);
            if (!line) continue;
            let msg; try { msg = JSON.parse(line); } catch { continue; }
            if (msg.id && this.pending.has(msg.id)) {
                const p = this.pending.get(msg.id);
                this.pending.delete(msg.id);
                if (msg.error) p.reject(new Error(JSON.stringify(msg.error)));
                else p.resolve(msg);
            }
        }
    }
    _call(method, params) {
        return new Promise((resolve, reject) => {
            const id = ++this.seq;
            this.pending.set(id, { resolve, reject });
            this.sock.write(JSON.stringify({ jsonrpc: "2.0", id, method, params: params || {} }) + "\n");
            setTimeout(() => {
                if (this.pending.has(id)) { this.pending.delete(id); reject(new Error("timeout: " + method)); }
            }, 30000);
        });
    }
    async init() {
        await this._call("initialize", { protocolVersion: "2024-11-05" });
        await this._call("initialized", {});
    }
    async tool(name, args = {}) {
        const resp = await this._call("tools/call", { name, arguments: args });
        const result = resp.result || {};
        if (result.isError) return { error: true, content: result.content };
        const content = result.content || [];
        let merged = {};
        for (const c of content) {
            if (c.type === "text") { try { merged = JSON.parse(c.text); } catch { merged = { raw: c.text }; } }
        }
        return merged;
    }
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function log(msg) { console.log("[" + new Date().toISOString().slice(11, 19) + "] " + msg); }

function printInteractables(analysis) {
    const interactables = analysis.interactables || [];
    log(`  Interactables (${interactables.length}):`);
    for (const it of interactables) {
        log(`    - "${it.text || '(no text)'}" @ center(${it.center.x},${it.center.y}) ${it.disabled ? '[DISABLED]' : ''}`);
    }
}

function printTexts(analysis) {
    const controls = (analysis.live || analysis).controls || [];
    log(`  Texts (${controls.length}):`);
    for (const c of controls) {
        if (c.text && c.text.trim()) {
            log(`    "${c.text}" [${c.kind || c.type || '?'}] path=${c.path}`);
        }
    }
}

async function main() {
    const client = new McpClient(HOST, PORT);
    await client.connect();
    await client.init();
    log("MCP connected.");

    // ===== Query game state =====
    log("=== Querying game state ===");

    const ships = await client.tool("game_ship_list");
    log("Ships: " + JSON.stringify(ships, null, 2).slice(0, 500));

    const research = await client.tool("game_research_status");
    log("Research: " + JSON.stringify(research, null, 2).slice(0, 500));

    const upgrades = await client.tool("game_upgrade_list");
    log("Upgrades: " + JSON.stringify(upgrades, null, 2).slice(0, 500));

    const resources = await client.tool("game_resources_all");
    log("Resources: " + JSON.stringify(resources, null, 2).slice(0, 1000));

    const factions = await client.tool("game_faction_query");
    log("Factions: " + JSON.stringify(factions, null, 2).slice(0, 500));

    const dispatch = await client.tool("game_dispatch_info");
    log("Dispatch: " + JSON.stringify(dispatch, null, 2).slice(0, 500));

    const planets = await client.tool("game_planet_info");
    log("Planets: " + JSON.stringify(planets, null, 2).slice(0, 1000));

    // Query GameState API methods
    log("\n=== GameState public methods ===");
    const gsApi = await client.tool("runtime_analyze_game_state");
    log("GameState methods: " + JSON.stringify(gsApi, null, 2).slice(0, 2000));

    fs.writeFileSync("_mcp_state_explore.json", JSON.stringify({
        ships, research, upgrades, resources, factions, dispatch, planets, gsApi
    }, null, 2));
    log("=== State exploration complete ===");
}

main().catch(e => { console.error("ERROR:", e.message); process.exit(1); });
