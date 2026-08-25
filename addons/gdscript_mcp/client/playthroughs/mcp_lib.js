// mcp_lib.js — Reusable MCP client library for SnipWar playthroughs
// Usage: const { McpClient, sleep, log } = require('./mcp_lib.js');

const net = require('net');
const fs = require('fs');
const path = require('path');

const HOST = '127.0.0.1';
const PORT = 9090;

class McpClient {
    constructor(host, port) {
        this.host = host || HOST;
        this.port = port || PORT;
        this.buf = '';
        this.seq = 0;
        this.pending = new Map();
        this.sock = null;
        this.connected = false;
    }

    connect() {
        return new Promise((resolve, reject) => {
            this.sock = net.connect(this.port, this.host);
            this.sock.on('connect', () => {
                this.sock.on('data', (d) => this._onData(d));
                this.sock.on('error', (e) => this._onError(e));
                this.sock.on('close', () => { this.connected = false; });
                this.connected = true;
                resolve();
            });
            this.sock.on('error', reject);
            setTimeout(() => reject(new Error('Connection timeout')), 8000);
        });
    }

    _onData(d) {
        this.buf += d.toString('utf8');
        let idx;
        while ((idx = this.buf.indexOf('\n')) >= 0) {
            const line = this.buf.slice(0, idx).trim();
            this.buf = this.buf.slice(idx + 1);
            if (!line) continue;
            let msg;
            try { msg = JSON.parse(line); } catch { continue; }
            if (msg.id != null && this.pending.has(msg.id)) {
                const p = this.pending.get(msg.id);
                this.pending.delete(msg.id);
                if (msg.error) p.reject(new Error(JSON.stringify(msg.error)));
                else p.resolve(msg.result);
            }
        }
    }

    _onError(e) {
        this.connected = false;
        // resolve pending with error
        for (const [id, p] of this.pending) {
            p.reject(new Error('Connection lost: ' + (e ? e.code : 'unknown')));
        }
        this.pending.clear();
    }

    _call(method, params, timeoutMs = 30000) {
        if (!this.connected) return Promise.reject(new Error('Not connected'));
        return new Promise((resolve, reject) => {
            const id = ++this.seq;
            this.pending.set(id, { resolve, reject });
            const payload = JSON.stringify({ jsonrpc: '2.0', id, method, params: params || {} }) + '\n';
            try { this.sock.write(payload); } catch (e) { this.pending.delete(id); reject(e); }
            setTimeout(() => {
                if (this.pending.has(id)) {
                    this.pending.delete(id);
                    reject(new Error('Tool timeout: ' + method));
                }
            }, timeoutMs);
        });
    }

    async init() {
        await this._call('initialize', { protocolVersion: '2024-11-05' });
        await this._call('initialized', {});
    }

    async tool(name, args = {}) {
        const resp = await this._call('tools/call', { name, arguments: args });
        if (!resp) return { error: 'Empty response' };
        const content = resp.content || [];
        let merged = {};
        for (const c of content) {
            if (c.type === 'text') {
                try { merged = JSON.parse(c.text); } catch { merged = { raw: c.text }; }
            }
        }
        if (resp.isError) merged._error = true;
        return merged;
    }

    disconnect() {
        this.connected = false;
        if (this.sock) { this.sock.destroy(); this.sock = null; }
    }
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

let _logFile = null;
let _uxNotes = [];

function log(msg, level) {
    const ts = new Date().toISOString().slice(11, 23);
    const line = `[${ts}] ${level || 'INFO'} ${msg}`;
    console.log(line);
    if (_logFile) fs.appendFileSync(_logFile, line + '\n');
}

function uxNote(severity, area, note) {
    const entry = { timestamp: new Date().toISOString(), severity, area, note };
    _uxNotes.push(entry);
    log(`UX ${severity.toUpperCase()} [${area}]: ${note}`, 'UX');
}

function setLogFile(filepath) { _logFile = filepath; }
function getUxNotes() { return _uxNotes; }

function printInteractables(analysis) {
    const controls = (analysis.live || analysis).controls || [];
    const interactables = controls.filter(c => c.interactable);
    log(`  Interactables (${interactables.length}):`);
    for (const c of interactables) {
        const disabled = c.disabled ? ' [DISABLED]' : '';
        const text = (c.text || '').trim();
        log(`    "${text}"${disabled} @ ${c.path || '?'}`);
    }
}

function printAllTexts(analysis) {
    const controls = (analysis.live || analysis).controls || [];
    const texts = controls.filter(c => c.text && c.text.trim());
    log(`  All texts (${texts.length}):`);
    for (const c of texts) {
        const flags = [(c.interactable ? 'I' : ''), (c.disabled ? 'D' : ''), (c.focused ? 'F' : '')].filter(Boolean).join('');
        log(`    "${c.text.trim()}" [${c.kind||c.type||'?'}] ${flags} ${c.path ? c.path.split('/').pop() : ''}`);
    }
}

// Helper: wait for a specific scene name
async function waitForScene(client, expectedScene, timeoutMs = 20000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        const scan = await client.tool('runtime_ux_scan');
        const scene = scan.scene || '?';
        if (scene === expectedScene) return true;
        await sleep(600);
    }
    return false;
}

module.exports = { McpClient, sleep, log, uxNote, setLogFile, getUxNotes, printInteractables, printAllTexts, waitForScene, HOST, PORT };