#!/usr/bin/env node
// Connector smoke test for the SnipWar MCP runtime server.
// Verifies the exact registration path a client takes: TCP connect ->
// initialize -> initialized -> tools/call. Read-only by contract: status,
// tool list and one UX scan of the live scene tree. No game mutation.
// Usage: MCP_PORT=9090 node addons/gdscript_mcp/client/mcp_connector_selftest.js
const path = require('path');
const { McpClient } = require(path.join(__dirname, 'playthroughs', 'mcp_lib.js'));

const PORT = Number(process.env.MCP_PORT || 9090);

async function main() {
	const client = new McpClient('127.0.0.1', PORT);
	await client.connect();
	await client.init();
	console.log('[selftest] connected + initialized on port ' + PORT);

	const status = await client.tool('runtime_mcp_status', {});
	console.log('[status] ' + JSON.stringify({
		role: status.role,
		running: status.running !== false && status.listening !== false,
		lifecycle_state: status.lifecycle_state || status.state || '',
		client_count: status.client_count,
		tool_count: status.tool_count,
		protocol_ready: status.protocol_ready,
	}));

	const listed = await client._call('tools/list', {});
	const names = ((listed && listed.tools) || []).map((t) => t.name);
	console.log('[tools] count=' + names.length);
	console.log('[tools] sample=' + JSON.stringify(names.slice(0, 8)));

	const scan = await client.tool('runtime_ux_scan', {});
	console.log('[ux_scan] scene=' + scan.scene + ' interactables=' + scan.count +
		' ui_ready=' + scan.ui_ready);

	client.disconnect();
	if (!names.length || !scan.scene || scan.count === undefined) {
		console.error('[selftest] FAIL — incomplete connector handshake');
		process.exit(1);
	}
	console.log('[selftest] PASS — initialize/status/tools-list/ux-scan all answered');
}

main().catch((e) => {
	console.error('[selftest] ERROR: ' + e.message);
	process.exit(1);
});
