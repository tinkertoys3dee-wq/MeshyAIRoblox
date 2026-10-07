// Compile the real Roblox sources, then run isolated behavior regressions in
// the Luau VM. Engine doubles do NOT replace Studio/device visual validation.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { LuauState } from 'luau-web';

const root = fileURLToPath(new URL('../../', import.meta.url));
const read = (name) => fs.readFileSync(path.join(root, name), 'utf8');
const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) =>
  entry.isDirectory() ? walk(path.join(dir, entry.name)) : [path.join(dir, entry.name)]);
const vm = await LuauState.createAsync();
// Isolate the WASM runtime for each suite: its heap is fixed, and closed
// state pointer caches are shared within one luau-web process.
const runSuite = async (source, name) => {
  const run = spawnSync(process.execPath, [fileURLToPath(new URL('./run-luau-suite.mjs', import.meta.url)), name], {
    input: source, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024,
  });
  if (run.status !== 0) {
    const detail = (run.stderr || String(run.error || 'Unknown failure')).split('\n').filter(line => line.length < 1000).slice(-8).join('\n');
    throw new Error(`${name} failed:\n${detail}`);
  }
  return JSON.parse(run.stdout.trim());
};
try {
  const files = walk(path.join(root, 'src')).filter((name) => name.endsWith('.luau'));
  for (const file of files) {
    const relative = path.relative(root, file);
    try {
      vm.loadstring(fs.readFileSync(file, 'utf8'), relative, true);
    } catch (error) {
      throw new Error(`Luau compilation failed in ${relative}: ${String(error).split('\n')[0]}`);
    }
  }
  console.log(`Compiled ${files.length} Luau source files.`);
  const modules = {
    AvatarLook: 'src/Shared/AvatarLook.luau',
    CatalogService: 'src/Server/Services/CatalogService.luau',
    MakeoverService: 'src/Server/Services/MakeoverService.luau',
    ItemService: 'src/Server/Services/ItemService.luau',
    Motion: 'src/Client/UI/Motion.luau',
    Factory: 'src/Client/UI/Factory.luau',
    GameShell: 'src/Client/UI/Games/GameShell.luau',
    NotificationService: 'src/Client/UI/NotificationService.luau',
    GroupJoin: 'src/Client/UI/GroupJoin.luau',
    AvatarLab: 'src/Client/UI/AvatarLab.luau',
    PlayerStateService: 'src/Server/Services/PlayerStateService.luau',
    WindowFocus: 'src/Client/UI/WindowFocus.luau',
    HomeAssets: 'src/Shared/HomeAssets.luau',
    DailyChallenge: 'src/Shared/DailyChallenge.luau',
    HomeEffects: 'src/Client/UI/HomeEffects.luau',
    PopupStyle: 'src/Client/UI/PopupStyle.luau',
    HomeScreen: 'src/Client/UI/HomeScreen.luau',
    ModernChrome: 'src/Client/UI/ModernChrome.luau',
    ModernLayouts: 'src/Client/UI/ModernLayouts.luau',
    ModernPageLayouts: 'src/Client/UI/ModernPageLayouts.luau',
    RedesignAssets: 'src/Shared/RedesignAssets.luau',
    RedesignMetrics: 'src/Shared/RedesignMetrics.luau',
    RedesignSkin: 'src/Client/UI/RedesignSkin.luau',
    RedesignCoreLayouts: 'src/Client/UI/RedesignCoreLayouts.luau',
    RedesignToolsLayouts: 'src/Client/UI/RedesignToolsLayouts.luau',
    RedesignGamesLayouts: 'src/Client/UI/RedesignGamesLayouts.luau',
  };
  const defineModulesFor = (names) => Object.entries(modules).filter(([name]) => !names || names.has(name)).map(([name, file]) =>
    `modules.${name} = function()\n${read(file)}\nend`).join('\n');
  const definitions = defineModulesFor();
  // Exercise the actual studio transition method without bootstrapping the
  // whole Roblox client. Keep the extraction fail-closed if it is renamed.
  const appSource = read('src/Client/UI/App.luau');
  const graphicsRenderer = appSource.match(/function App:_RenderAvatarGraphics\(\)[\s\S]*?(?=\nfunction App:)/)?.[0];
  if (!graphicsRenderer) throw new Error('Native Avatar Graphics renderer not found');
  const graphicsRendererModule = `modules.NativeGraphicsRenderer = function()
local App = {}; local Factory = require("Factory"); local Theme = require("Theme"); local Colors = Theme.Colors
local player = { UserId = 123 }
local Config = { Generation = { PromptMaxLength = 500,
  AvatarViews = { { Id = "HEADSHOT", Label = "Headshot", ThumbType = "AvatarHeadShot" }, { Id = "BUST", Label = "Bust", ThumbType = "AvatarBust" }, { Id = "FULL_BODY", Label = "Full body", ThumbType = "Avatar" } },
  ImageQualityTiers = { { Id = "LOW", ProductKey = "ImagePreviewLow" } }
} }
local function avatarThumbnail(userId, kind, size) return "rbxthumb://type=" .. kind .. "&id=" .. tostring(userId) .. "&w=" .. tostring(size) .. "&h=" .. tostring(size) end
local function gemForAccent() return "ForgeGemMint" end
${graphicsRenderer}
return App end`;
  const graphicsDiscoverRenderer = appSource.match(/function App:_RenderGraphicsDiscoverBody\(\)[\s\S]*?(?=\nfunction App:)/)?.[0];
  if (!graphicsDiscoverRenderer) throw new Error('Native public Graphics renderer not found');
  const graphicsDiscoverModule = `modules.NativeGraphicsDiscoverRenderer = function()
local App = {}; local Factory = require("Factory"); local Theme = require("Theme"); local Colors = Theme.Colors
local Network = require("Network")
local function directImage(id) return "rbxassetid://" .. tostring(id) end
local function formatNumber(value) return tostring(value) end
${graphicsDiscoverRenderer}
return App end`;
  const avatarLabSource = read('src/Client/UI/AvatarLab.luau');
  const gamesHubSource = read('src/Client/UI/GamesHub.luau');
  const motionSource = read('src/Client/UI/Motion.luau');
  const commerceSource = read('src/Server/Services/CommerceService.luau');
  const adRewardSource = read('src/Server/Services/AdRewardService.luau');
  const communitySource = read('src/Server/Services/CommunityService.luau');
  const playerStateSource = read('src/Server/Services/PlayerStateService.luau');
  const gameShellSource = read('src/Client/UI/Games/GameShell.luau');
  const arcadeGameFiles = files.filter((file) => {
    const relative = path.relative(root, file).split(path.sep).join('/');
    return relative.startsWith('src/Client/UI/Games/') && path.basename(file) !== 'GameShell.luau';
  });
  const scaledCanvasReaders = arcadeGameFiles
    .filter((file) => /canvas\.AbsoluteSize/.test(fs.readFileSync(file, 'utf8')))
    .map((file) => path.relative(root, file));
  if (scaledCanvasReaders.length > 0) {
    throw new Error(`Arcade games must use logical CanvasSize, not UIScale-multiplied AbsoluteSize: ${scaledCanvasReaders.join(', ')}`);
  }
  const unscaledPointerReaders = arcadeGameFiles
    .filter((file) => /(?:input\.Position|finish)\.[XY]\s*-\s*canvas\.AbsolutePosition\.[XY]/.test(fs.readFileSync(file, 'utf8')))
    .map((file) => path.relative(root, file));
  if (unscaledPointerReaders.length > 0) {
    throw new Error(`Arcade pointer input must use logical CanvasPoint coordinates: ${unscaledPointerReaders.join(', ')}`);
  }
  if (!gameShellSource.includes('function GameShell.CanvasSize')
    || !gameShellSource.includes('function GameShell.CanvasPoint')) {
    throw new Error('Arcade shell must retain shared scale-aware canvas and pointer helpers');
  }
  const deprecatedCommerceGates = files
    .filter((file) => /\bcommerceAllowed\b|COMMERCE_NOT_ALLOWED/.test(fs.readFileSync(file, 'utf8')))
    .map((file) => path.relative(root, file));
  if (deprecatedCommerceGates.length > 0) {
    throw new Error(`Obsolete Commerce Products gate remains in ${deprecatedCommerceGates.join(', ')}`);
  }
  for (const [name, source] of [
    ['CommerceService', commerceSource],
    ['AdRewardService', adRewardSource],
    ['AvatarLab', avatarLabSource],
  ]) {
    if (source.includes('commerceProductAllowed')) {
      throw new Error(`${name} must not gate standard Roblox purchases with real-world commerce policy`);
    }
  }
  if (!playerStateSource.includes('commerceProductAllowed')
    || !playerStateSource.includes('IsEligibleToPurchaseCommerceProduct')
    || !playerStateSource.includes('policyLookupSucceeded')) {
    throw new Error('Player policy state must retain a narrowly named, diagnostic Commerce Products result');
  }
  if (commerceSource.includes('playerStates') || adRewardSource.includes('playerStates')) {
    throw new Error('Standard purchase and rewarded-ad services must not depend on broad player policy state');
  }
  if (!communitySource.includes('PAID_TRADING_NOT_ALLOWED')) {
    throw new Error('Paid creator transfers must retain their exact policy failure reason');
  }
  if (!appSource.includes('generate.Active = true')) {
    throw new Error('The standard generation checkout button must remain available for Roblox to adjudicate');
  }
  if (gamesHubSource.includes('play.Active = false')) {
    throw new Error('The visible Arcade GO control must never swallow taps without activating');
  }
  if (!gamesHubSource.includes('play.Activated:Connect(activateTile)')
    || !gamesHubSource.includes('button.Activated:Connect(activateTile)')) {
    throw new Error('Both the visible Arcade GO control and the full game card must launch the tile');
  }
  if (!gamesHubSource.includes('transitionOverlay.Active = false')
    || !gamesHubSource.includes('transitionOverlay.Visible = false')) {
    throw new Error('Arcade transitions must remove their full-screen input shield after every switch');
  }
  if (!gamesHubSource.includes('Position = UDim2.new(1, -12, 0, 76)')) {
    throw new Error('Arcade challenge targets must stay out of the title row');
  }
  if (!avatarLabSource.includes('Name = "CatalogCategories"')
    || !/Name = "CatalogCategories"[\s\S]{0,180}ScrollBarThickness = [5-9]/.test(avatarLabSource)) {
    throw new Error('Catalog categories must expose a touch-friendly overflow scrollbar');
  }
  if (!appSource.includes('GuiService:GetGuiInset()') || !appSource.includes('Motion.AutoFocus(leave)')) {
    throw new Error('The AFK lounge exit must clear Roblox CoreGui and avoid pointer-only focus outlines');
  }
  if (!motionSource.includes('function Motion.AutoFocus')
    || !motionSource.includes('UserInputService:GetLastInputType()')) {
    throw new Error('Modal focus must be input-aware instead of drawing random pointer focus outlines');
  }
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
  for (const marker of [
    'WHAT DO YOU WANT TO DO?',
    'STYLE MY AVATAR · FREE',
    'MAKE MY OWN ITEM',
    'PLAY GAMES · FREE',
  ]) {
    if (!startGuideSource.includes(marker)) throw new Error(`First-session choice is missing ${marker}`);
  }
  if (!startGuideSource.includes('see the R$ %d price') || !startGuideSource.includes('Try catalog clothes and accessories')) {
    throw new Error('First-session choices must distinguish free try-on from paid generation');
  }
  if (!startGuideSource.includes('app.customUGCGuideRequested = false')) {
    throw new Error('Choosing a start path must not open a second tutorial automatically');
  }
  const primaryNav = appSource.match(/local PRIMARY_NAV = \{([\s\S]*?)\n\}/)?.[1];
  if (!primaryNav || (primaryNav.match(/\{ page =/g) || []).length !== 4) {
    throw new Error('Primary navigation must remain limited to four destinations');
  }
  for (const marker of ['page = "Home"', 'page = "Create"', 'page = "Avatar Lab"', 'page = "My Studio"']) {
    if (!primaryNav.includes(marker)) throw new Error(`Primary navigation is missing ${marker}`);
  }
  for (const marker of [
    'tokensCard.Visible = showAllMethods',
    'queueCard.Visible = showAllMethods',
    'daily.Visible = showAllMethods',
    'questCard.Visible = showAllMethods',
    'local visibleMethods = if showAllMethods then allMethods else {}',
  ]) {
    if (!appSource.includes(marker)) throw new Error(`Simple Create disclosure is missing ${marker}`);
  }
  for (const marker of ['CustomUGCGuide', 'CustomUGCGuideSteps', 'CustomUGCGuideArrow', 'CustomUGCPrompt', 'CreatePersonalUGCButton']) {
    if (!appSource.includes(marker)) throw new Error(`Personal UGC guide is missing ${marker}`);
  }
  if (!/Name = "CustomUGCGuideSteps"[\s\S]{0,420}ScrollBarThickness = [1-9]/.test(appSource)) {
    throw new Error('Personal UGC steps must expose a visible horizontal scrollbar');
  }
  if (!appSource.includes('UGC means an accessory you invent')) {
    throw new Error('The optional personal UGC guide must define UGC in plain language');
  }
  if (!appSource.includes('Publishing it to Roblox later is optional, separate')) {
    throw new Error('The personal UGC guide must separate in-game wear from optional Roblox publishing');
  }
  const transition = appSource.match(/function App:_SetStudioOpen\(open: boolean\)[\s\S]*?(?=\nfunction App:)/)?.[0];
  if (!transition) throw new Error('Studio transition method not found');
  const transitionModule = `modules.StudioTransition = function() local App = {}; local Motion = require("Motion"); ${transition}; return App end`;
  const suite = `${read('backend/tests/luau/engine-double.luau')}\n${definitions}\n${transitionModule}\n${read('backend/tests/luau/ui-avatar.spec.luau')}`;
  vm.destroy();
  const [count] = await runSuite(suite, 'ui-avatar-regressions');
  console.log(`Passed ${count} UI/avatar behavior assertions (engine doubles).`);
  const chrome = appSource.match(/function App:_ApplyHomeChrome\(\)[\s\S]*?(?=\nfunction App:)/)?.[0];
  if (!chrome) throw new Error('Home chrome transition method not found');
  const chromeModule = `modules.HomeChrome = function() local App = {}; local ModernChrome = require("ModernChrome"); ${chrome}; return App end`;
  const navigationInput = appSource.match(/-- Keyboard\/gamepad accessibility:[\s\S]*?UserInputService\.InputBegan:Connect\(function\(input, gameProcessed\)([\s\S]*?)\n\tend\)/)?.[1];
  if (!navigationInput) throw new Error('Studio keyboard/gamepad navigation callback not found');
  const navigationModule = `modules.NavigationFocus = function() local App = {}; local GuiService = game:GetService("GuiService"); function App:_TestNavigationInput(input, gameProcessed) ${navigationInput} end; return App end`;
  const homeSuite = `${read('backend/tests/luau/engine-double.luau')}\n${definitions}\n${chromeModule}\n${read('backend/tests/luau/home-screen.spec.luau')}`;
  const [homeCount] = await runSuite(homeSuite, 'home-screen-regressions');
  console.log(`Passed ${homeCount} Home behavior assertions (engine doubles).`);
  const effectsSuite = `${read('backend/tests/luau/engine-double.luau')}\n${definitions}\n${read('backend/tests/luau/home-effects.spec.luau')}`;
  const [effectsCount] = await runSuite(effectsSuite, 'home-effects-regressions');
  console.log(`Passed ${effectsCount} Home effects assertions (engine doubles).`);
  const popupDefinitions = defineModulesFor(new Set(['Motion', 'Factory', 'HomeAssets', 'PopupStyle']));
  const popupSuite = `${read('backend/tests/luau/engine-double.luau')}\n${popupDefinitions}\n${read('backend/tests/luau/popup-style.spec.luau')}`;
  const [popupCount] = await runSuite(popupSuite, 'popup-style-regressions');
  console.log(`Passed ${popupCount} popup style assertions (engine doubles).`);
  const modernSuite = `${read('backend/tests/luau/engine-double.luau')}\n${definitions}\n${navigationModule}\n${read('backend/tests/luau/modern-screen.spec.luau')}`;
  const [modernCount] = await runSuite(modernSuite, 'modern-screen-regressions');
  console.log(`Passed ${modernCount} modern screen assertions (engine doubles).`);
  const graphicsModules = new Set(['Motion', 'Factory', 'HomeAssets', 'HomeEffects', 'PopupStyle', 'HomeScreen', 'RedesignAssets', 'RedesignMetrics', 'RedesignSkin', 'RedesignToolsLayouts']);
  const graphicsDefinitions = defineModulesFor(graphicsModules);
  for (const name of ['core', 'games', 'tools']) {
    const suite = `${read('backend/tests/luau/engine-double.luau')}\n${name === 'tools' ? graphicsDefinitions : definitions}\n${read(`backend/tests/luau/redesign-${name}.spec.luau`)}`;
    const [count] = await runSuite(suite, `redesign-${name}-regressions`);
    console.log(`Passed ${count} redesigned ${name} assertions (engine doubles).`);
  }
  const graphicsSuite = `${read('backend/tests/luau/engine-double.luau')}\n${graphicsDefinitions}\n${graphicsRendererModule}\n${read('backend/tests/luau/redesign-graphics-native.spec.luau')}`;
  const [graphicsCount] = await runSuite(graphicsSuite, 'redesign-graphics-native-regressions');
  console.log(`Passed ${graphicsCount} native Graphics assertions (engine doubles).`);
  const discoverDefinitions = defineModulesFor(new Set(['Motion', 'Factory', 'RedesignSkin', 'ModernPageLayouts']));
  const discoverSuite = `${read('backend/tests/luau/engine-double.luau')}\n${discoverDefinitions}\n${graphicsDiscoverModule}\n${read('backend/tests/luau/graphics-discover.spec.luau')}`;
  const [discoverCount] = await runSuite(discoverSuite, 'graphics-discover-regressions');
  console.log(`Passed ${discoverCount} native Graphics Discover assertions (engine doubles).`);
} finally {
  if (!vm.destroyed) vm.destroy();
}
