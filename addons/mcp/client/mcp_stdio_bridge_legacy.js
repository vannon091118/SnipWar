#!/usr/bin/env node
// Stdio↔TCP bridge: exposes the SnipWar MCP runtime (default 127.0.0.1:9090)
// as a local stdio connector so any MCP client can register it via .mcp.json.
// One JSON-RPC message per line, bidirectional passthrough, zero dependencies.
// Diagnostics go to stderr ONLY — stdout carries protocol traffic exclusively.
//
// Requires a VISIBLE running game:  $GODOT_BIN --path . -- --mcp --mcp-port 9090
//
// Stabilität:
//  * Wiederholte Connect-Versuche (Server startet asynchron im Editor —
//    Initial-Connect kann fehlschlagen, wenn der Editor noch nicht bereit ist).
//  * Write-Bufferung für STDIN-Eingaben, bis die TCP-Verbindung offen ist
//    (sonst gehen erste Calls des Clients verloren, bevor der Server lauscht).
//  * Graceful Shutdown mit 1.5 s Antwort-Flush, damit die letzte Anfrage nicht
//    im Nirvana verschwindet, wenn stdin direkt nach dem letzten Call schließt.
const net = require('net');
const readline = require('readline');

const HOST = process.env.MCP_HOST || '127.0.0.1';
const PORT = Number(process.env.MCP_PORT || 9090);
const CONNECT_RETRY_MS = 750;
const CONNECT_RETRY_MAX = 40; // ~30 s, danach hart aufgeben

let sock = null;
let connectAttempts = 0;
let closed = false;
let pendingWrites = [];

function tryConnect() {
	if (closed) return;
	sock = net.connect(PORT, HOST);
	sock.setNoDelay(true);

	sock.on('connect', () => {
		connectAttempts = 0;
		// Flush der zwischenzeitlich eingegangenen STDIN-Zeilen
		for (const line of pendingWrites) sock.write(line + '\n');
		pendingWrites = [];
	});

	let sbuf = '';
	sock.on('data', (d) => {
		sbuf += d.toString('utf8');
		let idx;
		while ((idx = sbuf.indexOf('\n')) >= 0) {
			const line = sbuf.slice(0, idx);
			sbuf = sbuf.slice(idx + 1);
			if (line.trim()) process.stdout.write(line.trim() + '\n');
		}
	});

	sock.on('error', (e) => {
		// Erste Fehler sind oft ECONNREFUSED während Server-Boot — silent retry.
		if (connectAttempts < CONNECT_RETRY_MAX) {
			connectAttempts++;
			setTimeout(tryConnect, CONNECT_RETRY_MS);
			return;
		}
		console.error('[snipwar-mcp-bridge] tcp error: ' + (e && e.code ? e.code : e) +
			' — start the game first: "$GODOT_BIN" --path . -- --mcp --mcp-port ' + PORT);
		process.exit(1);
	});

	sock.on('close', () => {
		if (closed) return;
		// Unerwarteter Drop (Server-Crash). Reconnect für resilience.
		if (connectAttempts < CONNECT_RETRY_MAX) {
			connectAttempts++;
			setTimeout(tryConnect, CONNECT_RETRY_MS);
		}
	});
}

tryConnect();

const rb = readline.createInterface({ input: process.stdin, terminal: false });
rb.on('line', (line) => {
	const t = line.trim();
	if (!t) return;
	if (sock && sock.writable) {
		sock.write(t + '\n');
	} else {
		// Verbindungsaufbau läuft noch — puffern statt verwerfen.
		pendingWrites.push(t);
	}
});
rb.on('close', () => {
	closed = true;
	// Flush pending replies before exiting so the last request's answer still
	// reaches the client even when stdin closes right after the final call.
	setTimeout(() => process.exit(0), 1500);
});
