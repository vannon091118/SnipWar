#!/usr/bin/env node
// Persistent direct-execution transport: ONE process + ONE handshake for the
// whole run, so repeated actions no longer pay per-action process/TCP/handshake
// overhead ("Vor-/Nachlaufzeit"). Commands are appended as JSON lines to a
// commands file; each command executes EXACTLY ONE MCP tool call; results are
// appended to an output file. The live-player atom contract stays intact: one
// tool call per command, and the agent decides the next command only after
// reading the previous result.
//
// Usage:
//   MCP_PORT=9090 MCP_COMMANDS=/tmp/mcp_cmds.jsonl MCP_OUTPUT=/tmp/mcp_out.jsonl \
//     node mcp_file_driver.js            # start once, keep it running
//   echo '{"tool":"runtime_ux_scan","args":{}}' >> /tmp/mcp_cmds.jsonl
//   tail -1 /tmp/mcp_out.jsonl           # one result line per command
//   echo '{"command":"close"}' >> /tmp/mcp_cmds.jsonl   # clean shutdown
const fs = require('fs');
const { McpClient } = require('../mcp_lib.js');

const PORT = Number(process.env.MCP_PORT || 9090);
const COMMANDS_FILE = process.env.MCP_COMMANDS || '/tmp/mcp_cmds.jsonl';
const OUTPUT_FILE = process.env.MCP_OUTPUT || '/tmp/mcp_out.jsonl';
const POLL_MS = 120;

function appendOutput(entry) {
  fs.appendFileSync(OUTPUT_FILE, JSON.stringify(entry) + '\n');
}

async function main() {
  if (fs.existsSync(OUTPUT_FILE)) fs.rmSync(OUTPUT_FILE);
  const client = new McpClient('127.0.0.1', PORT);
  await client.connect();
  await client.init();
  appendOutput({ ready: true, transport: 'file', one_tool_call_per_line: true });

  let offset = 0;
  let closing = false;
  while (!closing) {
    let lines = [];
    if (fs.existsSync(COMMANDS_FILE)) {
      const data = fs.readFileSync(COMMANDS_FILE, 'utf8');
      const parts = data.split('\n');
      // Last part is either the empty string after a trailing newline or a
      // partial write — never process it before it is complete.
      const completeCount = parts.length - 1;
      lines = parts.slice(offset, completeCount);
      offset = completeCount;
    }
    for (const line of lines) {
      if (!line.trim()) continue;
      let request;
      try {
        request = JSON.parse(line);
      } catch (error) {
        appendOutput({ ok: false, error: 'invalid JSON command' });
        continue;
      }
      if (request.command === 'close') {
        closing = true;
        break;
      }
      if (typeof request.tool !== 'string' || request.tool.length === 0) {
        appendOutput({ ok: false, error: 'tool is required' });
        continue;
      }
      const started = Date.now();
      try {
        const result = await client.tool(request.tool, request.args || {});
        appendOutput({ ok: true, tool: request.tool, elapsed_ms: Date.now() - started, result });
      } catch (error) {
        appendOutput({ ok: false, tool: request.tool, elapsed_ms: Date.now() - started, error: error.message });
      }
    }
    await new Promise((resolve) => setTimeout(resolve, POLL_MS));
  }
  client.disconnect();
  appendOutput({ closed: true });
}

main().catch((error) => {
  process.stderr.write(((error && error.stack) || String(error)) + '\n');
  process.exitCode = 1;
});
