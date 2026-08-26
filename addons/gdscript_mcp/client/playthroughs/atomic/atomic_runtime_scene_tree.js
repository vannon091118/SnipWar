#!/usr/bin/env node
// One observation action: inspect the live scene tree.
const { runSingle, parseArgs, numberArg } = require('./atomic_client.js');
const args = parseArgs(process.argv.slice(2));
runSingle('runtime_get_scene_tree', {
  max_depth: numberArg(args, 'maxDepth', 4),
  root_path: String(args.rootPath || '/root'),
  max_nodes: numberArg(args, 'maxNodes', 200),
}).catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
