// Render a local visual approximation from the actual HomeScreen instance tree.
// Uses deterministic Roblox doubles for layout; Studio remains the engine check.
import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.dirname(here);
const require = createRequire(path.join(root, 'backend/package.json'));
const { LuauState } = await import(pathToFileURL(require.resolve('luau-web')).href);
const playwrightPath = process.env.FORGE_PLAYWRIGHT_MODULE;
if (!playwrightPath) throw new Error('Set FORGE_PLAYWRIGHT_MODULE to an installed playwright package path.');
const { chromium } = require(playwrightPath);
const read = file => fs.readFile(path.join(root, file), 'utf8');
const definitions = [];
for (const [name, file] of Object.entries({ Motion: 'src/Client/UI/Motion.luau', Factory: 'src/Client/UI/Factory.luau',
  HomeAssets: 'src/Shared/HomeAssets.luau', HomeEffects: 'src/Client/UI/HomeEffects.luau', HomeScreen: 'src/Client/UI/HomeScreen.luau' })) {
  definitions.push(`modules.${name} = function()\n${await read(file)}\nend`);
}
const vm = await LuauState.createAsync();
const manifest = JSON.parse(await read('design/home/manifest.json'));
const ids = JSON.parse(await read('design/home/asset_ids.json'));
const paths = Object.fromEntries(manifest.map(item => [String(ids[item.name]), item.file]));
const script = `
local app = {
 content = Instance.new("Frame"), gui = Instance.new("ScreenGui"), uiScaleInstance = Instance.new("UIScale"),
 pageConnections = {}, state = { profile = { tokens = 0, bonusTokens = 0, retryCredits = {} } },
 _BindButton = function() end, _TrackScroll = function() end, _Track = function() end, _OpenPage = function() end,
}
require("HomeScreen").Render(app)
local root = app.content:FindFirstChild("ForgeHome")
root.AbsoluteSize = Vector2.new(WIDTH, HEIGHT)
for _, child in root:GetDescendants() do
 if child.ClassName == "ImageLabel" then child.IsLoaded = true end
end
-- Snapshot the settled page after the staggered entrance.
while #delayed > 0 do table.remove(delayed, 1)() end
local function size(v) return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset } end
local function color(c) return c and { c.R, c.G, c.B } or nil end
local function pack(n)
 local p = { name=n.Name, kind=n.ClassName, pos=size(n.Position), size=size(n.Size),
   anchor=n.AnchorPoint and {n.AnchorPoint.X,n.AnchorPoint.Y} or {0,0}, z=n.ZIndex or 1,
   bg=color(n.BackgroundColor3), alpha=n.BackgroundTransparency or 0, children={} }
 if n.ClassName == "TextLabel" or n.ClassName == "TextButton" then
   p.text = (n.TextTransparency or 0) < 1 and n.Text or ""
   p.color=color(n.TextColor3); p.font=n.Font and n.Font.Name; p.fontSize=n.TextSize
   p.align=n.TextXAlignment and n.TextXAlignment.Name; p.valign=n.TextYAlignment and n.TextYAlignment.Name
   p.rotation=n.Rotation or 0
 end
 if n.ClassName == "ImageLabel" then p.image=n.Image; p.fit=n.ScaleType.Name end
 for _, child in n:GetChildren() do
   if child.ClassName == "UIScale" then p.scale=child.Scale
   elseif child.ClassName == "UICorner" then p.radius=child.CornerRadius.Offset
   elseif child.ClassName == "UIStroke" and child.Transparency < 1 then p.stroke={color(child.Color),child.Thickness,child.Transparency}
   elseif child.ClassName == "UIGradient" and child.Enabled ~= false then
     p.gradient={}; p.gradientRotation=child.Rotation
     for _, point in (child.Color.Keypoints or child.Color[1]) do table.insert(p.gradient,color(point.Value or point[2])) end
   elseif child:IsA("GuiObject") and not string.match(child.ClassName,"^UI") then table.insert(p.children,pack(child)) end
 end
 return p
end
local function quote(s)
 return '"' .. s:gsub('\\\\','\\\\\\\\'):gsub('"','\\\\"'):gsub('\\n','\\\\n'):gsub('\\r','\\\\r'):gsub('\\t','\\\\t') .. '"'
end
local function json(v)
 if type(v)=="string" then return quote(v) elseif type(v)=="number" then return tostring(v)
 elseif type(v)=="boolean" then return tostring(v) elseif type(v)=="table" then
   local items={}
   if #v>0 then for _, item in v do table.insert(items,json(item)) end return "["..table.concat(items,",").."]" end
   for k,item in v do table.insert(items,quote(k)..":"..json(item)) end return "{"..table.concat(items,",").."}"
 end
 return "null"
end
return json(pack(root))
`;
const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const color = (value, opacity = 1) => value ? `rgba(${value.map(x => Math.round(x * 255)).join(',')},${opacity})` : 'transparent';
const dim = (scale, offset) => `calc(${scale * 100}% + ${offset}px)`;
function element(node) {
  const style = { position: 'absolute', left: dim(...node.pos.slice(0, 2)), top: dim(...node.pos.slice(2)),
    width: dim(...node.size.slice(0, 2)), height: dim(...node.size.slice(2)), zIndex: node.z,
    backgroundColor: color(node.bg, 1 - node.alpha), borderRadius: `${node.radius || 0}px`,
    transformOrigin: `${node.anchor[0] * 100}% ${node.anchor[1] * 100}%`,
    transform: `translate(${-node.anchor[0] * 100}%,${-node.anchor[1] * 100}%) scale(${node.scale || 1}) rotate(${node.rotation || 0}deg)` };
  if (node.kind === 'ScrollingFrame') style.overflowY = 'auto';
  if (node.stroke) style.outline = `${node.stroke[1]}px solid ${color(node.stroke[0], 1 - node.stroke[2])}`;
  if (node.gradient?.length) style.backgroundImage = `linear-gradient(${(node.gradientRotation || 0) + 90}deg,${node.gradient.map(x => color(x)).join(',')})`;
  let inner = '';
  if (node.image) {
    const id = node.image.split('://').pop();
    inner += `<img src="${paths[id]}" style="width:100%;height:100%;object-fit:${node.fit === 'Fit' ? 'contain' : node.fit === 'Crop' ? 'cover' : 'fill'}">`;
  }
  if (node.text) {
    const textStyle = { width: '100%', height: '100%', display: 'flex', alignItems: node.valign === 'Top' ? 'flex-start' : 'center',
      justifyContent: node.align === 'Center' ? 'center' : node.align === 'Right' ? 'flex-end' : 'flex-start',
      textAlign: node.align.toLowerCase(), font: `${node.font?.includes('Bold') || node.font?.includes('Black') ? '800' : '400'} ${node.fontSize}px Arial,sans-serif`,
      lineHeight: '1.2', color: color(node.color), whiteSpace: 'pre-wrap', textShadow: node.name === 'Caption' && node.fontSize > 25 ? '0 3px 2px #00194e' : 'none' };
    if (node.gradient?.length) { style.backgroundImage = ''; textStyle.backgroundImage = `linear-gradient(180deg,${node.gradient.map(x => color(x)).join(',')})`; textStyle.backgroundClip = 'text'; textStyle.color = 'transparent'; textStyle.textShadow = 'none'; textStyle.WebkitTextStroke = '1px #020918'; }
    inner += `<span style="${css(textStyle)}">${escape(node.text)}</span>`;
  }
  inner += (Array.isArray(node.children) ? node.children : []).map(element).join('');
  return `<div data-name="${escape(node.name)}" style="${css(style)}">${inner}</div>`;
}
function css(style) { return Object.entries(style).map(([key, value]) => `${key.replace(/[A-Z]/g, letter => '-' + letter.toLowerCase())}:${value}`).join(';'); }
const browser = await chromium.launch({ headless: true });
try {
  for (const [name, width, height] of [['desktop', 1672, 941], ['phone', 390, 844]]) {
    const suite = `${await read('backend/tests/luau/engine-double.luau')}\n${definitions.join('\n')}\nlocal WIDTH,HEIGHT=${width},${height}\n${script}`;
    const [snapshot] = await vm.loadstring(suite, `home-${name}`, true)();
    const tree = JSON.parse(snapshot);
    tree.size = [0, width, 0, height];
    const html = `<!doctype html><meta charset="utf-8"><title>Forge Home ${name} preview</title><style>html,body{margin:0;background:#0f182c;overflow:hidden}*{box-sizing:border-box}img{display:block}::-webkit-scrollbar{width:4px}::-webkit-scrollbar-thumb{background:#00caff}</style>${element(tree)}`;
    const file = path.join(here, 'home', `preview-${name}.html`);
    await fs.writeFile(file, html);
    const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
    await page.goto(new URL(`file:///${file.replaceAll('\\', '/')}`).href);
    await page.evaluate(async () => { await document.fonts.ready; await Promise.all(Array.from(document.images).map(image => image.decode().catch(() => {}))); });
    await page.screenshot({ path: path.join(here, 'home', `preview-${name}.png`) });
    if (name === 'phone') {
      await page.locator('[data-name="HomeScroll"]').evaluate(node => { node.scrollTop = node.scrollHeight; });
      await page.screenshot({ path: path.join(here, 'home', 'preview-phone-shortcuts.png') });
    }
    console.log(`Rendered ${name} from HomeScreen.luau at ${width}x${height}.`);
    await page.close();
  }
} finally { await browser.close(); vm.destroy(); }
