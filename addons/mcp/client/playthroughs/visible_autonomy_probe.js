const { McpClient, sleep } = require('./mcp_lib.js');

async function main() {
  const port = Number(process.env.MCP_PORT || 9090);
  const client = new McpClient('127.0.0.1', port);
  await client.connect();
  await client.init();

  const listed = await client._call('tools/list');
  const tools = listed.tools || [];
  const autonomyTools = tools.filter(t => String(t.name || '').startsWith('runtime_autonomy_'));
  const contractTools = tools.filter(t => t.autonomy_contract_version === 'mcp.autonomy.v1');
  console.log(JSON.stringify({
    stage: 'tools_list',
    total_tools: tools.length,
    autonomy_tools: autonomyTools.map(t => t.name),
    contract_tools: contractTools.length,
    sample_metadata: contractTools.slice(0, 3).map(t => ({
      name: t.name,
      access: t.access,
      scope: t.scope,
      visibility: t.visibility,
      requires: t.requires,
      produces: t.produces,
      postconditions: t.postconditions,
      evidence: t.evidence,
      mutates: t.mutates,
      rollback: t.rollback,
      async: t.async,
    })),
  }, null, 2));

  const blocked = await client.tool('runtime_autonomy_plan', {
    intent: 'nonexistent capability',
    required_outputs: ['never_produced'],
    mode: 'visible',
  });
  console.log(JSON.stringify({
    stage: 'blocked_plan',
    verdict: blocked.verdict,
    reason: blocked.reason,
    missing_capabilities: blocked.missing_capabilities,
    selected_steps: (blocked.steps || []).length,
    mutations: blocked.rollback && blocked.rollback.mutations,
  }, null, 2));

  const plan = await client.tool('runtime_autonomy_plan', {
    intent: 'visible capability probe',
    required_outputs: ['scene_observation'],
    mode: 'visible',
  });
  console.log(JSON.stringify({
    stage: 'visible_plan',
    verdict: plan.verdict,
    reason: plan.reason,
    selected: plan.selection && (plan.selection.selected || []).map(s => s.tool),
    steps: (plan.steps || []).map(s => ({
      step_id: s.step_id,
      tool: s.tool,
      requires: s.requires,
      produces: s.produces,
      postconditions: s.postconditions,
      evidence: s.evidence,
      mutates: s.mutates,
      rollback: s.rollback,
    })),
  }, null, 2));

  const status = await client.tool('runtime_mcp_status');
  console.log(JSON.stringify({
    stage: 'mcp_status',
    state: status.state,
    role: status.role,
    session_id: status.session_id,
    renderer: status.renderer,
    running: status.running,
    tool_count: status.tool_count,
  }, null, 2));

  const receipt = await client.tool('runtime_autonomy_probe', {
    intent: 'visible capability probe',
    required_outputs: ['scene_observation'],
  });
  console.log(JSON.stringify({
    stage: 'visible_probe_receipt',
    receipt_version: receipt.receipt_version,
    run_id: receipt.run_id,
    verdict: receipt.verdict,
    reason: receipt.reason,
    probe: receipt.probe,
    step_count: (receipt.steps || []).length,
    steps: (receipt.steps || []).map(s => ({
      step_id: s.step_id,
      tool: s.tool,
      verdict: s.verdict,
      preconditions_ok: s.preconditions && s.preconditions.ok,
      postconditions_ok: s.postconditions && s.postconditions.ok,
      evidence_complete: s.evidence && s.evidence.complete,
      rollback: s.rollback,
    })),
    evidence: receipt.evidence,
    rollback: receipt.rollback,
  }, null, 2));

  const latest = await client.tool('runtime_autonomy_receipt');
  console.log(JSON.stringify({
    stage: 'receipt_readback',
    same_run: latest.run_id === receipt.run_id,
    verdict: latest.verdict,
  }, null, 2));

  client.disconnect();
}

main().catch(err => {
  console.error('VISIBLE_MCP_PROBE_ERROR', err.stack || err.message);
  process.exitCode = 1;
});
