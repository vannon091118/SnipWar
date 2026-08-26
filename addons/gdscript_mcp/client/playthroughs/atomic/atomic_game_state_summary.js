#!/usr/bin/env node
// One observation action: read one game-state summary.
const { runSingle, parseArgs } = require('./atomic_client.js');
const args = parseArgs(process.argv.slice(2));
runSingle('game_state_summary', {
  faction: String(args.faction || 'a'),
}).catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
