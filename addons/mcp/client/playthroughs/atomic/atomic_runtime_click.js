#!/usr/bin/env node
// One ingame action: one press/release click. Target discovery is deliberately
// not performed here; the sequence composes find, move and click separately.
const { runSingle, parseArgs, numberArg } = require('./atomic_client.js');
const args = parseArgs(process.argv.slice(2));
const payload = {
  path: String(args.path || ''),
  x: numberArg(args, 'x', -1),
  y: numberArg(args, 'y', -1),
  hold_frames: numberArg(args, 'holdFrames', 2),
};
if (args.injectMode) payload.inject_mode = String(args.injectMode);
runSingle('runtime_click', payload).catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
