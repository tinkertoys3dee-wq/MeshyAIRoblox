// Fresh WASM process for one behavior suite. Sources arrive through stdin.
import fs from 'node:fs';
import { LuauState } from 'luau-web';
const vm = await LuauState.createAsync();
try {
  const run = vm.loadstring(fs.readFileSync(0, 'utf8'), process.argv[2] || 'behavior-suite', true);
  process.stdout.write(JSON.stringify(await run()) + '\n');
} catch (error) {
  process.stderr.write(String(error).split('\n').filter(line => line.length < 1000).slice(0, 8).join('\n') + '\n');
  process.exitCode = 1;
} finally {
  vm.destroy();
}
