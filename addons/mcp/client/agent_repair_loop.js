#!/usr/bin/env node
/*
 * Autonomous Repair & Feature Loop Orchestrator for SnipWar MCP (JS).
 *
 * Executes the closed-loop autonomous lifecycle — the exact 8 steps that
 * agent_repair_loop.py used to run, now on the single JS client core
 * (mcp_lib.js). No second protocol client, no language split:
 *
 *   1. Initialize & Handshake
 *   2. Baseline Snapshot & Resource Read
 *   3. Journaled Workspace Sandbox Begin
 *   4. Import & Atomic Single-Occurrence Patch
 *   5. Validation & Gated Export with Resource Barrier Settlement
 *   6. Headless Verification (Preflight / Contract Chains)
 *   7. Visible Runtime Verification (Freeze/Step & Goal Sequences)
 *   8. Verdict & Rollback-on-Failure / Archive-on-Success
 *
 * Usage (requires a VISIBLE running game with runtime MCP, profile qa|dev):
 *   node agent_repair_loop.js --port 9090 --file res://scripts/foo.gd \
 *     --old "old text" --new "new text" --goal "fix xyz"
 *   # optional: --chain chain.json --sequence sequence.json
 */
const path = require('path');
const fs = require('fs');
const { McpClient } = require(path.join(__dirname, 'playthroughs', 'mcp_lib.js'));

const PORT = Number(process.env.MCP_PORT || 9090);

function parseArgs(argv) {
  const args = { port: PORT, file: '', old: '', new: '', goal: 'smoke_test', chain: '', sequence: '' };
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--port') args.port = Number(argv[++i]) || PORT;
    else if (arg === '--file') args.file = argv[++i] || '';
    else if (arg === '--old') args.old = argv[++i] || '';
    else if (arg === '--new') args.new = argv[++i] || '';
    else if (arg === '--goal') args.goal = argv[++i] || 'smoke_test';
    else if (arg === '--chain') args.chain = argv[++i] || '';
    else if (arg === '--sequence') args.sequence = argv[++i] || '';
  }
  return args;
}

function readJsonArg(filePath) {
  if (!filePath) return null;
  const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  return Array.isArray(parsed) ? parsed : parsed.steps || null;
}

async function main() {
  const args = parseArgs(process.argv);

  const client = new McpClient('127.0.0.1', args.port);
  await client.connect();
  await client.init();
  console.log('[1/8] Handshake OK on port ' + args.port);

  // 2. Baseline via MCP resource (authoritative summary, read-only).
  console.log('[2/8] Baseline snapshot via godot://gameState/summary ...');
  const baselineResp = await client._call('resources/read', { uri: 'godot://gameState/summary' });
  // resources/read-Contents sind {uri, mimeType, text} — KEIN type-Feld
  // (das gibt es nur bei tools/call-Content). Direct auf c.text parsen.
  let baseline = {};
  for (const c of (baselineResp && baselineResp.contents) || []) {
    if (c && typeof c.text === 'string') {
      try { baseline = JSON.parse(c.text); } catch { /* keep {} */ }
    }
  }
  console.log('      Baseline faction=' + (baseline.faction || '?') + ' homeworld=' + (baseline.homeworld || '?'));

  // 3. Open journaled workspace sandbox.
  console.log('[3/8] Opening isolated workspace sandbox ...');
  const wsBegin = await client.tool('runtime_autonomy_workspace_begin', { project_id: 'snipwar' });
  if (!wsBegin.ok) {
    console.error('[BLOCKED] workspace begin failed: ' + JSON.stringify(wsBegin));
    process.exitCode = 1;
    return;
  }
  const sessionId = (wsBegin.workspace && wsBegin.workspace.session_id) || '';
  console.log('      Workspace active: run_id=' + ((wsBegin.workspace && wsBegin.workspace.run_id) || '?'));

  const fail = async (reason, details) => {
    console.error('[FAIL] ' + reason + ': ' + JSON.stringify(details));
    const rb = await client.tool('runtime_autonomy_rollback_all', {});
    await client.tool('runtime_autonomy_workspace_end', {});
    console.log('      Rollback: ' + (rb.ok ? 'ok' : JSON.stringify(rb)));
    process.exitCode = 1;
  };

  // 4. Import + atomic single-occurrence patch.
  console.log('[4/8] Importing ' + args.file + ' and applying patch ...');
  const imp = await client.tool('runtime_autonomy_workspace_import', { path: args.file });
  if (!imp.ok) return fail('import failed', imp);
  const patch = await client.tool('runtime_autonomy_patch', {
    path: imp.workspace_path || '',
    old_text: args.old,
    new_text: args.new,
  });
  if (!patch.ok) return fail('patch failed', patch);
  console.log('      Patch applied (tx ' + (patch.transaction_id || '?') + ')');

  // 5. Gated export with resource barrier.
  console.log('[5/8] Validating + exporting (apply=true) ...');
  const exp = await client.tool('runtime_autonomy_export', { path: args.file, apply: true });
  if (!exp.ok) return fail('export validation failed', exp);
  console.log('      Export ok (barrier ' + ((exp.resource_barrier && exp.resource_barrier.duration_ms) || '?') + ' ms)');

  // 6. Optional headless verification chain.
  const chainSteps = readJsonArg(args.chain);
  if (chainSteps) {
    console.log('[6/8] Running declarative verification chain ...');
    const chain = await client.tool('runtime_chain_run', { name: 'verify_' + args.goal, steps: chainSteps });
    if (chain.verdict !== 'PASS') return fail('chain verification failed', chain);
    console.log('      Chain PASSED (' + (chain.completed_steps || 0) + ' steps)');
  } else {
    console.log('[6/8] No --chain file — skipping declarative verification.');
  }

  // 7. Optional visible gameplay sequence.
  const seqSteps = readJsonArg(args.sequence);
  if (seqSteps) {
    console.log('[7/8] Running visible gameplay sequence ...');
    const seq = await client.tool('runtime_goal_sequence', { actions: seqSteps });
    if (seq.verdict !== 'PASS') return fail('visible sequence failed', seq);
    console.log('      Visible sequence PASSED.');
  } else {
    console.log('[7/8] No --sequence file — skipping visible verification.');
  }

  // 8. Conclude: finalize workspace, archive trace.
  console.log('[8/8] Finalizing run workspace ...');
  await client.tool('runtime_autonomy_workspace_end', {});
  console.log('>>> AUTONOMOUS REPAIR CYCLE: VERDICT = PASS <<<');
  console.log(JSON.stringify({ verdict: 'PASS', goal: args.goal, target: args.file, session_id: sessionId }));
}

main().catch((e) => {
  console.error('[agent-repair-loop] ERROR: ' + (e && e.message ? e.message : e));
  process.exit(1);
});