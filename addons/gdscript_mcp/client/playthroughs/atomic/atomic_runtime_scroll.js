#!/usr/bin/env node
// One ingame action: one visible virtual mouse-wheel scroll gesture.
// Use only after a live scan reports a scrollable panel or truncated scope.
const { runSingle, parseArgs, numberArg } = require('./atomic_client.js');
const args = parseArgs(process.argv.slice(2));
const payload = {
  path: String(args.path || ''),
  x: numberArg(args, 'x', -1),
  y: numberArg(args, 'y', -1),
  direction: String(args.direction || 'down'),
  steps: numberArg(args, 'steps', 1),
};
runSingle('runtime_scroll', payload).catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
