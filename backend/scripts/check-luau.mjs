// Compile the real Roblox sources, then run isolated behavior regressions in
// the Luau VM. Engine doubles do NOT replace Studio/device visual validation.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { LuauState } from 'luau-web';

const root = fileURLToPath(new URL('../../', import.meta.url));
const read = (name) => fs.readFileSync(path.join(root, name), 'utf8');
const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) =>
  entry.isDirectory() ? walk(path.join(dir, entry.name)) : [path.join(dir, entry.name)]);
const vm = await LuauState.createAsync();
try {
  const files = walk(path.join(root, 'src')).filter((name) => name.endsWith('.luau'));
  for (const file of files) vm.loadstring(fs.readFileSync(file, 'utf8'), path.relative(root, file), true);
  console.log(`Compiled ${files.length} Luau source files.`);
  const modules = {
    AvatarLook: 'src/Shared/AvatarLook.luau',
    CatalogService: 'src/Server/Services/CatalogService.luau',
    ItemService: 'src/Server/Services/ItemService.luau',
    Motion: 'src/Client/UI/Motion.luau',
    Factory: 'src/Client/UI/Factory.luau',
    NotificationService: 'src/Client/UI/NotificationService.luau',
    AvatarLab: 'src/Client/UI/AvatarLab.luau',
    WindowFocus: 'src/Client/UI/WindowFocus.luau',
  };
  const definitions = Object.entries(modules).map(([name, file]) =>
    `modules.${name} = function()\n${read(file)}\nend`).join('\n');
  // Exercise the actual studio transition method without bootstrapping the
  // whole Roblox client. Keep the extraction fail-closed if it is renamed.
  const appSource = read('src/Client/UI/App.luau');
  const transition = appSource.match(/function App:_SetStudioOpen\(open: boolean\)[\s\S]*?(?=\nfunction App:)/)?.[0];
  if (!transition) throw new Error('Studio transition method not found');
  const transitionModule = `modules.StudioTransition = function() local App = {}; local Motion = require("Motion"); ${transition}; return App end`;
  const suite = `${read('backend/tests/luau/engine-double.luau')}\n${definitions}\n${transitionModule}\n${read('backend/tests/luau/ui-avatar.spec.luau')}`;
  const run = vm.loadstring(suite, 'ui-avatar-regressions', true);
  const [count] = await run();
  console.log(`Passed ${count} UI/avatar behavior assertions (engine doubles).`);
} finally {
  vm.destroy();
}
