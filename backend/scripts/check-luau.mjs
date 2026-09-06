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
    MakeoverService: 'src/Server/Services/MakeoverService.luau',
    ItemService: 'src/Server/Services/ItemService.luau',
    Motion: 'src/Client/UI/Motion.luau',
    Factory: 'src/Client/UI/Factory.luau',
    NotificationService: 'src/Client/UI/NotificationService.luau',
    GroupJoin: 'src/Client/UI/GroupJoin.luau',
    AvatarLab: 'src/Client/UI/AvatarLab.luau',
    PlayerStateService: 'src/Server/Services/PlayerStateService.luau',
    WindowFocus: 'src/Client/UI/WindowFocus.luau',
  };
  const definitions = Object.entries(modules).map(([name, file]) =>
    `modules.${name} = function()\n${read(file)}\nend`).join('\n');
  // Exercise the actual studio transition method without bootstrapping the
  // whole Roblox client. Keep the extraction fail-closed if it is renamed.
  const appSource = read('src/Client/UI/App.luau');
  for (const name of ['FitActions', 'SharingActions', 'TipOptions']) {
    const scrollingRow = new RegExp(`Factory\\.New\\("ScrollingFrame", \\{[\\s\\S]{0,120}Name = "${name}"`);
    if (!scrollingRow.test(appSource)) throw new Error(`${name} must remain an overflow-safe ScrollingFrame`);
  }
  if (!appSource.includes('Factory.LabelPadding(button, 15, 0)')) {
    throw new Error('Navigation caption padding must not offset icon children');
  }
  for (const name of [
    'IdeaSuggestions',
    'ChoiceOptions',
    'ReferenceQualityOptions',
    'FitRegionOptions',
    'MarketplaceFilters',
    'GraphicsMarketplaceFilters',
    'GraphicsChoiceOptions',
    'GraphicsQualityOptions',
  ]) {
    const visibleScroller = new RegExp(`Name = "${name}"[\\s\\S]{0,640}ScrollBarThickness = [1-9]`);
    if (!visibleScroller.test(appSource)) throw new Error(`${name} must expose a visible scrollbar`);
  }
  for (const file of [
    'src/Client/UI/App.luau',
    'src/Client/UI/AvatarLab.luau',
    'src/Client/UI/GamesHub.luau',
  ]) {
    const source = read(file);
    const hiddenHorizontal = /ScrollBarThickness\s*=\s*0,[\s\S]{0,180}ScrollingDirection\s*=\s*Enum\.ScrollingDirection\.X/;
    if (hiddenHorizontal.test(source)) throw new Error(`${file} hides a horizontal overflow scrollbar`);
  }
  const avatarLabSource = read('src/Client/UI/AvatarLab.luau');
  for (const name of ['MakeoverObjectives', 'StarterLooks']) {
    const visibleScroller = new RegExp(`Name = "${name}"[\\s\\S]{0,420}ScrollBarThickness = [1-9]`);
    if (!visibleScroller.test(avatarLabSource)) throw new Error(`${name} must expose a visible scrollbar`);
  }
  for (const marker of ['GuidedMakeoverCard', 'GuideProgress', 'GuideArrow', 'GuideTargetGlow', 'GuidedChangeCategories', 'ForgeGuideTarget']) {
    if (!avatarLabSource.includes(marker)) throw new Error(`Contextual makeover guide is missing ${marker}`);
  }
  if (!appSource.includes('catalogAccess = true :: boolean?')) {
    throw new Error('Catalog search must not be blocked by unrelated inventory-read consent');
  }
  const startGuideSource = read('src/Client/UI/StartGuide.luau');
  if (!startGuideSource.includes('there is no free first generation')) {
    throw new Error('First-session copy must distinguish free try-on from paid generation');
  }
  if (!startGuideSource.includes('START GUIDED MAKEOVER') || !startGuideSource.includes('TutorialPath')) {
    throw new Error('First-session tutorial must promise and preview the guided three-step path');
  }
  if (!startGuideSource.includes('TutorialPathArrow') || !startGuideSource.includes('Motion.Pulse(connector')) {
    throw new Error('The opening tutorial path must expose large animated connectors');
  }
  for (const marker of ['CustomUGCGuide', 'CustomUGCGuideSteps', 'CustomUGCGuideArrow', 'CustomUGCPrompt', 'CreatePersonalUGCButton']) {
    if (!appSource.includes(marker)) throw new Error(`Personal UGC guide is missing ${marker}`);
  }
  if (!/Name = "CustomUGCGuideSteps"[\s\S]{0,420}ScrollBarThickness = [1-9]/.test(appSource)) {
    throw new Error('Personal UGC steps must expose a visible horizontal scrollbar');
  }
  if (!startGuideSource.includes('CustomUGCExplanation') || !startGuideSource.includes('CREATE PERSONAL UGC')) {
    throw new Error('The opening tutorial must explain and clearly route personal UGC creation');
  }
  if (!appSource.includes('UGC means an accessory you invent') || !startGuideSource.includes('PERSONAL UGC = an accessory you invent')) {
    throw new Error('Personal UGC must be defined in plain language before checkout');
  }
  if (!appSource.includes('Publishing it to Roblox later is optional, separate')) {
    throw new Error('The personal UGC guide must separate in-game wear from optional Roblox publishing');
  }
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
