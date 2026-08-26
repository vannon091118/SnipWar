#!/usr/bin/env node
// One ingame action: move the virtual mouse once.
const { runSingle, parseArgs, numberArg } = require('./atomic_client.js');
const args = parseArgs(process.argv.slice(2));
runSingle('runtime_mouse_move', {
  x: numberArg(args, 'x', 0),
  y: numberArg(args, 'y', 0),
}).catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
