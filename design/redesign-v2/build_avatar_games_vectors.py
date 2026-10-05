"""Measured reconstruction of three new generated UI mockups.

Decorative samples are individually path traced. All interface geometry and
lettering stays native editable SVG. No game code, assets or credentials.
"""
from pathlib import Path
from copy import deepcopy
import concurrent.futures
import html
import json
import subprocess
import sys
import xml.etree.ElementTree as ET
from PIL import ImageFont

HERE = Path(__file__).resolve().parent
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)
ET.register_namespace('xlink', 'http://www.w3.org/1999/xlink')
HOME = ET.parse(HERE.parent / 'home/forge-ugc.svg').getroot()
ART = HERE / 'artwork'
OUT = HERE / 'svg'
OUT.mkdir(exist_ok=True)

JOBS = [
 ('avatar-lab','LabHairArt',(80,478,307,202),[(343,488,40,42)]),
 ('avatar-lab','LabCrownArt',(413,480,304,202),[(675,488,40,42)]),
 ('avatar-lab','LabHoodieArt',(740,480,308,202),[(1006,488,40,42)]),
 ('avatar-lab','LabAvatarArt',(1066,398,276,436),[]),
 ('avatar-lab','LabWornHairArt',(1364,459,52,51),[]),
 ('avatar-lab','LabWornCrownArt',(1364,524,52,51),[]),
 ('avatar-lab','LabWornHoodieArt',(1364,589,52,51),[]),
 ('avatar-lab','LabWornPantsArt',(1364,654,52,51),[]),
 ('avatar-lab','LabWornShoesArt',(1364,719,52,51),[]),
 ('avatar-graphics','GraphicsAvatarArt',(93,408,249,252),[]),
 ('avatar-graphics','GraphicsNeonPosterArt',(1012,329,283,370),[]),
 ('avatar-graphics','GraphicsPurplePosterArt',(1319,329,283,370),[]),
 ('avatar-graphics','GraphicsJobThumbArt',(139,818,75,65),[]),
 ('games','GamesArcadeSceneArt',(72,454,503,337),[]),
 ('games','GamesRunwaySceneArt',(597,454,497,337),[]),
 ('games','GamesLoungeSceneArt',(1121,454,491,337),[]),
]

def trace(job):
    screen,name,bounds,excludes=job
    target=ART / (name+'.svg')
    if target.exists() and '--retrace' not in sys.argv: return
    args=[sys.executable,str(HERE/'trace_artwork.py'),str(HERE/'mockups'/f'{screen}.png'),str(target),'--crop',','.join(map(str,bounds)),'--name',name,'--colors','8','--layer-difference','4','--speckle','1','--length-threshold','2']
    for rect in excludes: args += ['--exclude',','.join(map(str,rect))]
    run=subprocess.run(args,capture_output=True,text=True)
    if run.returncode: raise RuntimeError(run.stderr)
    print('Traced '+name,flush=True)

def native(tag,attrs='',inner=''):
    return f'<{tag} {attrs}>{inner}</{tag}>'

class Screen:
    def __init__(self,slug,title,active):
        self.slug=slug; self.title=title; self.count=0; self.parts=[]
        defs=deepcopy(HOME.find('{'+NS+'}defs'))
        self.parts.append(ET.tostring(defs,encoding='unicode'))
        self.parts.append('''<defs>
<linearGradient id="v2-blue" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#02dafa"/><stop offset=".14" stop-color="#02befe"/><stop offset="1" stop-color="#0060ff"/></linearGradient>
<linearGradient id="v2-purple" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#d951ff"/><stop offset=".18" stop-color="#a02eff"/><stop offset="1" stop-color="#6a00ea"/></linearGradient>
<linearGradient id="v2-gold" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#ffe64d"/><stop offset=".22" stop-color="#ffbb11"/><stop offset="1" stop-color="#ff8b00"/></linearGradient>
<linearGradient id="v2-dark" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#224c7c"/><stop offset="1" stop-color="#101d3a"/></linearGradient>
<linearGradient id="v2-shell" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#08213b"/><stop offset=".45" stop-color="#0d1529"/><stop offset="1" stop-color="#1b213c"/></linearGradient>
<linearGradient id="v2-field" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#102a4a"/><stop offset="1" stop-color="#101b38"/></linearGradient>
<linearGradient id="v2-violet-panel" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#3e0d79"/><stop offset=".45" stop-color="#201344"/><stop offset="1" stop-color="#321053"/></linearGradient>
<linearGradient id="v2-gold-panel" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#8e5100"/><stop offset=".5" stop-color="#653300"/><stop offset="1" stop-color="#603500"/></linearGradient>
<radialGradient id="v2-card-blue"><stop stop-color="#074b74"/><stop offset="1" stop-color="#001d35"/></radialGradient>
<radialGradient id="v2-card-purple"><stop stop-color="#42156c"/><stop offset="1" stop-color="#261037"/></radialGradient>
<radialGradient id="v2-avatar-panel"><stop stop-color="#143e71"/><stop offset="1" stop-color="#061930"/></radialGradient>
<linearGradient id="v2-games-blue-panel" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#00538f"/><stop offset=".45" stop-color="#072e6d"/><stop offset="1" stop-color="#013a73"/></linearGradient>
<linearGradient id="v2-games-purple-panel" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#500977"/><stop offset=".45" stop-color="#3b0b62"/><stop offset="1" stop-color="#250448"/></linearGradient>
<linearGradient id="v2-games-gold-panel" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#995813"/><stop offset=".4" stop-color="#824300"/><stop offset="1" stop-color="#5f2a02"/></linearGradient>
<linearGradient id="v2-red"><stop stop-color="#4e2119"/><stop offset="1" stop-color="#330d13"/></linearGradient>
</defs>''')
        city=deepcopy(next(x for x in HOME if x.get('id')=='blurred-city-backdrop'))
        city.set('data-component','background')
        self.parts.append(ET.tostring(city,encoding='unicode'))
        self.panel('MainShell',45,112,1591,789,'url(#v2-shell)','#52627e',34,4)
        self.parts.append('<rect x="54" y="122" width="1573" height="769" rx="27" fill="none" stroke="#0d5781" stroke-width="1.5"/>')
        self.resource(1145,29,199,'coin','250','AddTokens')
        self.resource(1359,29,191,'ticket','12','AddPasses')
        self.button('Settings',1573,29,64,64,'',style='plain',icon='gear',icon_size=38)
        logo=deepcopy(next(x for x in HOME if x.get('id')=='forge-ugc-logo'))
        logo.set('data-component','brand'); self.parts.append(ET.tostring(logo,encoding='unicode'))
        self.panel('PrimaryNav',385,136,963,77,'#071629','#2b3b59',19,2)
        nav=[('Home',386,235,'home'),('Create',621,249,'cube'),('Market',870,227,'bag'),('Games',1097,250,'game')]
        for label,x,w,icon in nav:
            self.button('Nav'+label,x,137,w,75,label,style='blue' if label==active else 'flat',icon=icon,fs=27,icon_size=36)
        self.button('MyItems',1360,140,184,68,'My Items',style='purple' if slug=='avatar-lab' else 'dark',icon='bag',fs=23,icon_size=31)
        self.button('Close',1562,141,63,66,'',style='plain',icon='close',icon_size=35)

    def text(self,x,y,value,size=22,fill='#f4f8ff',weight=400,anchor='start',width=None,shadow=False,extra=''):
        attrs=f'x="{x}" y="{y}" font-size="{size}" fill="{fill}" font-weight="{weight}" text-anchor="{anchor}"'
        if width:
            fontfile='ariblk.ttf' if weight>=900 else ('arialbd.ttf' if weight>=600 else 'arial.ttf')
            actual=ImageFont.truetype('C:/Windows/Fonts/'+fontfile,size).getlength(str(value))
            attrs=f'x="0" y="{y}" transform="translate({x} 0) scale({width/actual} 1)" font-size="{size}" fill="{fill}" font-weight="{weight}" text-anchor="{anchor}" data-editable-width="{width}"'
        if shadow: attrs += ' filter="url(#text-shadow)"'
        self.parts.append(f'<text {attrs} {extra}>{html.escape(str(value))}</text>')

    def panel(self,name,x,y,w,h,fill='#071c34',stroke='#264c73',r=16,sw=2):
        component='field' if name.endswith('Field') else 'panel'
        self.parts.append(f'<g id="{name}" data-component="{component}"><g id="{name}Art" data-asset="{name}Art" data-bounds="{x} {y} {w} {h}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/></g></g>')

    def icon(self,name,x,y,s=24,color='#f3f8ff',asset=None):
        self.count+=1
        iid=asset or f'{self.slug.replace("-","")}Icon{self.count}'
        paths={
        'home':'<path d="M2 10 12 2 22 10v2h-3v10h-5v-7h-4v7H5V12H2Z" fill="currentColor"/>',
        'cube':'<path d="m2 7 10-5 10 5-10 6Zm0 2 9 5v9L2 18Zm20 0-9 5v9l9-5Z" fill="currentColor"/>',
        'bag':'<path d="M5 8h14l2 14H3Z" fill="currentColor"/><path d="M8 9V6a4 4 0 0 1 8 0v3" fill="none" stroke="currentColor" stroke-width="2.3"/>',
        'game':'<path d="M7 5h10q3 0 4 4l3 10q1 3-2 3l-6-5H8l-6 5q-3 0-2-3l3-10q1-4 4-4Z" fill="currentColor"/><path d="M7 9v7m-3-3h7" stroke="#08477c" stroke-width="2.4"/><circle cx="17" cy="10" r="1.4" fill="#08477c"/><circle cx="20" cy="13" r="1.4" fill="#08477c"/>',
        'close':'<path d="m4 4 16 16M20 4 4 20" stroke="currentColor" stroke-width="4.4" stroke-linecap="round"/>',
        'plus':'<path d="M12 3v18M3 12h18" stroke="currentColor" stroke-width="4"/>',
        'gear':'<path d="m9 1 6 0 1 4 3 2 4 0 2 5-3 3 0 4-4 3-4-2-3 1-3 3-5-2 0-4-3-3 2-5 4 0 2-3Z" fill="currentColor"/><circle cx="12" cy="12" r="4.7" fill="#0e1b30"/>',
        'search':'<circle cx="10" cy="10" r="7" fill="none" stroke="currentColor" stroke-width="2.5"/><path d="m15 15 7 7" stroke="currentColor" stroke-width="2.5"/>',
        'hanger':'<path d="M10 5q0-5 5-3t-1 6l-1 2 10 10q2 2-1 2H2q-3 0-1-2L12 9" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linejoin="round"/>',
        'heart':'<path d="M12 22 3 13Q-2 8 2 4t10 1q6-7 10-1t-1 9Z" fill="none" stroke="currentColor" stroke-width="2.2"/>',
        'bookmark':'<path d="M5 2h14v21l-7-5-7 5Z" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linejoin="round"/>',
        'avatar':'<circle cx="12" cy="6" r="4" fill="currentColor"/><path d="M4 23v-6q0-6 8-6t8 6v6Z" fill="currentColor"/>',
        'body':'<circle cx="12" cy="3" r="2.7" fill="currentColor"/><path d="M7 9h10l3 9-2 1-3-7v12h-3v-8h-1v8H8V12l-3 7-2-1Z" fill="currentColor"/>',
        'shirt':'<path d="m2 7 5-5 3 2h4l3-2 5 5-3 5-3-2v13H8V10l-3 2Z" fill="currentColor"/>',
        'hat':'<path d="M3 14q2-11 9-11 8 0 9 11l-6 3-3-3-7 2Z" fill="currentColor"/><path d="m2 16 10-3 10 4-3 3-17-2Z" fill="currentColor"/>',
        'hair':'<path d="M2 8q4-9 10-6 7-3 10 6l-1 12-4 2-1-11-2-5-3 6-3-4-1 14-5-3Z" fill="currentColor"/>',
        'face':'<circle cx="6" cy="7" r="2" fill="currentColor"/><circle cx="18" cy="7" r="2" fill="currentColor"/><path d="M4 14q8 12 16 0" stroke="currentColor" stroke-width="2.4" fill="none"/>',
        'pants':'<path d="M5 1h14l1 22h-7l-1-14-1 14H4Z" fill="currentColor"/><path d="M7 4h10" stroke="#1b2b47" stroke-width="1"/>',
        'jacket':'<path d="m2 6 6-4 4 7 4-7 6 4 2 17-6 0-2-12v12H8V11L6 23H0Z" fill="currentColor"/><path d="M12 9v14" stroke="#1b2b47" stroke-width="2"/>',
        'more':'<circle cx="3" cy="12" r="2.7" fill="currentColor"/><circle cx="12" cy="12" r="2.7" fill="currentColor"/><circle cx="21" cy="12" r="2.7" fill="currentColor"/>',
        'reset':'<path d="M21 9a10 10 0 1 0-1 10M21 9l-6-1m6 1 0-6" stroke="currentColor" stroke-width="2.4" fill="none" stroke-linecap="round"/>',
        'chevron':'<path d="m5 8 7 7 7-7" stroke="currentColor" stroke-width="2.5" fill="none" stroke-linecap="round"/>',
        'mouse':'<rect x="5" y="1" width="14" height="22" rx="7" stroke="currentColor" stroke-width="2.1" fill="none"/><path d="M12 2v8m-6 1h12" stroke="currentColor" stroke-width="1.8"/>',
        'picture':'<rect x="2" y="2" width="20" height="20" rx="3" stroke="currentColor" stroke-width="2.1" fill="none"/><path d="m4 20 7-8 5 5 3-4 3 7Z" fill="currentColor"/><circle cx="8" cy="7" r="2" fill="currentColor"/>',
        'brush':'<path d="m11 13 8-11q3-2 3 2L14 15Z" fill="currentColor"/><path d="M12 14q6 4-1 8-5 3-9-1 6 0 6-4Z" fill="currentColor"/>',
        'palette':'<path d="M12 2q12 0 12 10 0 5-6 4-5-1-3 5-12 4-14-7T12 2Z" fill="currentColor"/><circle cx="7" cy="8" r="1.4" fill="#1e335b"/><circle cx="13" cy="6" r="1.4" fill="#1e335b"/><circle cx="19" cy="10" r="1.4" fill="#1e335b"/><circle cx="5" cy="14" r="1.4" fill="#1e335b"/>',
        'wrench':'<path d="M21 1q-3 0-4 3l3 3 4-2q2 9-7 10L7 25l-5-5 11-11q-2-8 8-8Z" fill="currentColor"/>',
        'star':'<path d="m12 0 3 8 9 4-9 4-3 8-3-8-9-4 9-4Z" fill="currentColor"/>',
        'info':'<circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 10v8" stroke="currentColor" stroke-width="2.5"/><circle cx="12" cy="6" r="1.5" fill="currentColor"/>',
        'clock':'<circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 5v8l5 3" stroke="currentColor" stroke-width="2.5" fill="none"/>',
        'trash':'<path d="M5 7h14l-1 16H6Z" fill="currentColor"/><path d="M3 5h18M9 2h6" stroke="currentColor" stroke-width="2.2"/>',
        'link':'<path d="m14 7 4-4q4-3 6 1t-1 5l-5 5q-4 3-7-1m-1 4-4 4q-4 3-6-1t1-5l5-5q4-3 7 1M7 17 17 7" fill="none" stroke="currentColor" stroke-width="2.5"/>',
        'external':'<path d="M13 2h9v9M22 2 10 14M10 4H3v18h18v-8" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linejoin="round"/>',
        'coin':'<ellipse cx="13" cy="13" rx="10.5" ry="11" fill="#d88609"/><ellipse cx="12" cy="12" rx="10" ry="11" fill="url(#coin)" stroke="#fff58a" stroke-width="1.3"/><ellipse cx="12" cy="12" rx="7" ry="8" fill="none" stroke="#e99702" stroke-width=".8"/><path d="m15 6-7 2 0 4 7 3-1 4-7-2m6-13-2 18" fill="none" stroke="#fff9a0" stroke-width="2"/><path d="M5 15Q2 8 9 4" fill="none" stroke="#fff9c7" stroke-opacity=".65" stroke-width=".8"/>',
        'ticket':'<g transform="rotate(-40 12 12)"><path d="M2 5h20v5q-5 2 0 4v5H2v-5q5-2 0-4Z" fill="#00c8f4" stroke="#b9fcff" stroke-width="1.5"/><path d="m10 9 5 0v6h-5Z" fill="none" stroke="#efffff"/></g>',
        }
        if name not in paths: raise ValueError(name)
        self.parts.append(f'<g id="{iid}" data-component="icon" data-asset="{iid}" data-bounds="0 0 24 24" transform="translate({x} {y}) scale({s/24})" style="color:{color}">{paths[name]}</g>')

    def button(self,name,x,y,w,h,label,style='dark',icon=None,fs=20,icon_size=25,align='center',action=None):
        fills={'blue':'url(#v2-blue)','purple':'url(#v2-purple)','gold':'url(#v2-gold)','dark':'url(#v2-dark)','plain':'#09162a','flat':'none','red':'url(#v2-red)'}
        strokes={'blue':'#00deff','purple':'#d778ff','gold':'#ffe552','dark':'#4c6da4','plain':'#344966','flat':'none','red':'#cf6b5e'}
        self.parts.append(f'<g id="{name}" data-component="button" data-action="{action or name}">')
        if style!='flat':
            glow=' filter="url(#cyan-glow)"' if name.startswith('Nav') and style=='blue' else ''
            self.parts.append(f'<g id="{name}Art" data-asset="{name}Art" data-bounds="{x} {y} {w} {h}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{min(18,h/3)}" fill="{fills[style]}" stroke="{strokes[style]}" stroke-width="2"{glow}/><path d="M{x+16} {y+2}H{x+w-16}" stroke="#fff" stroke-opacity=".2"/></g>')
        total=(len(label)*fs*.51)+(icon_size+12 if icon and label else 0)
        left=x+(w-total)/2 if align=='center' else x+18
        if icon:
            ix=left if label else x+(w-icon_size)/2
            self.icon(icon,ix,y+(h-icon_size)/2,icon_size,'#001e37' if style=='gold' else '#ff5b6d' if style=='red' else '#f1f6ff',name+'Icon')
        if label:
            tx=left+(icon_size+12 if icon else 0)
            label_role=' data-role="LiveGenerationPriceLabel"' if name=='GraphicsGenerate' else ''
            self.text(tx,y+h/2+fs*.35,label,fs,'#ff8b90' if style=='red' else '#f7fbff',700,shadow=style in ['blue','purple','gold'],extra=label_role)
        self.parts.append('</g>')

    def resource(self,x,y,w,icon,value,action):
        self.panel(action+'Counter',x,y,w,64,'url(#resource-bg)','#334b6b',21,2)
        self.icon(icon,x+12,y+8,46)
        self.text(x+66,y+42,value,29,weight=700,extra='data-role="LiveCurrencyValue"')
        self.button(action,x+w-52,y+11,42,42,'','blue','plus',icon_size=28)

    def art(self,name,role=None):
        job=next(j for j in JOBS if j[1]==name)
        x,y,w,h=job[2]
        root=ET.parse(ART/(name+'.svg')).getroot()
        traced_defs=root.find(f'{{{NS}}}defs')
        if traced_defs is not None:
            self.parts.append(ET.tostring(deepcopy(traced_defs),encoding='unicode'))
        group=deepcopy(next(n for n in root if n.tag==f'{{{NS}}}g'))
        group.set('transform',f'translate({x} {y})')
        if role: group.set('data-role',role)
        self.parts.append(ET.tostring(group,encoding='unicode'))

    def write(self,notes):
        desc=html.escape('Measured native vector reconstruction of the newly generated '+self.title+' screen. Illustrated media are individually traced sample placeholders; labels and controls remain editable. '+notes)
        result=f'<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="{NS}" xmlns:xlink="http://www.w3.org/1999/xlink" width="1672" height="941" viewBox="0 0 1672 941" role="img" aria-labelledby="ScreenTitle ScreenDescription" font-family="Arial, sans-serif"><title id="ScreenTitle">Forge UGC — {self.title}</title><desc id="ScreenDescription">{desc}</desc>\n'+ '\n'.join(self.parts)+'</svg>\n'
        (OUT/(self.slug+'.svg')).write_text(result,encoding='utf-8')

def avatar_lab():
    s=Screen('avatar-lab','Avatar Lab','Create')
    s.icon('hanger',79,242,79,'#16d6ff','LabTitleIcon')
    s.text(188,285,'Avatar Lab',55,weight=900,width=312,shadow=True)
    s.text(189,316,'Build a look that feels like you.',24,'#b9ddf8',600)
    s.panel('LabSecondaryNav',578,244,1030,67,'#071b34','#2b466b',17)
    s.button('LabWorkspaceTab',578,243,301,66,'Avatar Lab','blue','hanger',23,34)
    s.button('LabGraphicsTab',882,244,382,66,'Avatar Graphics','flat','palette',23,34)
    s.button('LabMoreTools',1267,244,341,66,'More tools','flat','wrench',23,34)
    s.parts.append('<path d="M1264 258V297" stroke="#406999" stroke-width="2"/>')
    s.panel('CatalogWorkspace',63,330,990,555,'#071c31','#00caff',23,1.5)
    s.panel('CatalogSearchField',78,341,775,53,'url(#v2-field)','#4b658e',15)
    s.icon('search',98,354,28,'#b6cffc','CatalogSearchIcon')
    s.text(148,376,'Search the Roblox catalog...',22,'#adbedf')
    s.button('CatalogSearch',868,341,180,54,'Search','blue',fs=21)
    cats=[('Hair',78,98,'hair'),('Hats',187,101,'hat'),('Face',298,98,'face'),('Shirts',407,108,'shirt'),('Pants',526,106,'pants'),('Jackets',642,120,'jacket'),('Back',774,99,'bag'),('More filters',885,163,'more')]
    for label,x,w,icon in cats: s.button('Category'+label.replace(' ',''),x,409,w,49,label,'blue' if label=='Hair' else 'plain',icon,16,25)
    cards=[(78,313,'Cyber Nova Hair','Forge UGC',75,'LabHairArt'),(409,312,'Shadow Crown','PixelForge',125,'LabCrownArt'),(738,313,'Neon Tech Hoodie','StyleLab',85,'LabHoodieArt')]
    for i,(x,w,name,creator,price,art) in enumerate(cards):
        prefix=f'CatalogCard{i+1}'
        s.panel(prefix,x,478,w,404,'url(#v2-card-purple)' if i==1 else 'url(#v2-card-blue)','#b640ee' if i==1 else '#00baff',20)
        s.art(art,'ReplaceWithLiveCatalogThumbnail')
        s.button(prefix+'BookmarkHeart',x+w-44,490,30,33,'','flat','heart',icon_size=26)
        s.text(x+14,702,name,22,weight=700,extra='data-role="LiveCatalogName"')
        s.text(x+14,731,'By '+creator,19,'#d8ddff',extra='data-role="LiveCatalogCreator"')
        s.text(x+16,760,f'R$ {price}',20,weight=700,extra='data-role="LiveCatalogOwnershipPrice"')
        s.parts.append(f'<g id="{prefix}ViewInRoblox" data-component="button" data-action="PromptCatalogPurchase" data-bounds="{x+w-162} 739 148 26">')
        s.text(x+w-159,759,'View in Roblox',16)
        s.icon('external',x+w-36,744,17,asset=prefix+'ViewInRobloxIcon')
        s.parts.append('</g>')
        s.button(prefix+'TryOn',x+12,773,w-26,44,'Try on','blue','hanger',20,25)
        s.button(prefix+'Bookmark',x+12,827,w-26,43,'Bookmark','dark','bookmark',18,23,action='SaveVisitBookmark')
    s.panel('AvatarStage',1061,331,557,555,'url(#v2-avatar-panel)','#04aefd',23)
    s.text(1084,379,'Your Avatar',36,weight=900,width=228)
    s.button('ResetAvatarCamera',1397,344,207,47,'Reset camera','dark','reset',17,23,align='left')
    s.icon('chevron',1569,356,22,asset='ResetCameraOptionsIcon')
    s.art('LabAvatarArt','ReplaceWithLiveAvatarViewport')
    s.panel('WornItemsPanel',1345,404,263,476,'#041b30','#304d77',19)
    s.text(1359,437,'Wearing (5)',21,weight=700,extra='data-role="LiveWornCount"')
    worn=[('Cyber Nova Hair','LabWornHairArt'),('Shadow Crown','LabWornCrownArt'),('Neon Tech Hoodie','LabWornHoodieArt'),('Tech Cargo Pants','LabWornPantsArt'),('Neon Runners','LabWornShoesArt')]
    for i,(name,art) in enumerate(worn):
        y=455+i*65
        s.panel(f'WornRow{i+1}',1359,y,240,61,'url(#v2-field)','#243c62',12,1.2)
        s.art(art,'ReplaceWithLiveWornThumbnail')
        s.text(1428,y+35,name,14,extra='data-role="LiveWornItemName"')
        s.button(f'RemoveWorn{i+1}',1559,y+12,33,35,'','plain','close',icon_size=19,action='RemoveWornItem')
    s.button('SaveNewLook',1360,805,241,66,'Save as new look','purple','bookmark',18,30,action='SaveInForge')
    s.button('DragAvatarToRotate',1110,838,176,47,'Drag to rotate','dark','mouse',17,26,action='RotateAvatarViewport')
    s.write('Catalog prices use R$ rather than Forge tokens. Card controls explicitly use visit bookmarks and View in Roblox. Sample names, prices and outfit are live-data placeholders.')

def avatar_graphics():
    s=Screen('avatar-graphics','Avatar Graphics','Create')
    s.panel('GraphicsComposer',61,229,918,666,'url(#v2-violet-panel)','#db76ff',24,2.5)
    s.parts.append('<path d="M63 325 190 231h255L76 492v-49l246-210H189Z" fill="#993dff" opacity=".12"/><path d="M797 231 430 596h-120l367-365Z" fill="#8630ff" opacity=".05"/>')
    s.icon('star',86,253,43,'#fff','GraphicsTitleSparkle1');s.icon('star',119,252,14,'#fff','GraphicsTitleSparkle2');s.icon('star',85,291,13,'#fff','GraphicsTitleSparkle3')
    s.text(149,291,'Avatar Graphics',53,weight=900,width=421,shadow=True)
    s.text(151,321,'Turn your look into something shareable.',21)
    s.panel('GraphicsTabs',611,250,355,63,'#251157','#7545b1',14)
    s.button('GraphicsCreateTab',612,253,174,58,'Create','purple','brush',23,28)
    s.button('GraphicsDiscoverTab',787,253,178,58,'Discover','flat','search',20,26)
    s.panel('GraphicsForm',77,344,887,429,'#171144','#68399a',19,1.6)
    for n,y in [(1,372),(2,425),(3,522)]:
        s.parts.append(f'<circle cx="{105 if n==1 else 379}" cy="{y}" r="17" fill="url(#v2-purple)" stroke="#d3a2ff" stroke-width="1.7"/>')
        s.text(105 if n==1 else 379,y+7,n,23,weight=700,anchor='middle')
    s.text(137,379,'Choose a source',21,weight=700)
    s.button('GraphicsMyAvatarSource',362,353,281,46,'My Avatar','blue','avatar',20,27,action='SetAvatarGraphicsSource')
    s.button('GraphicsTextSource',654,354,297,46,'Describe an image','plain','picture',18,26,action='SetTextGraphicsSource')
    s.panel('GraphicsSourceThumbnail',90,405,253,259,'#145e98','#9c7cff',15)
    s.art('GraphicsAvatarArt','ReplaceWithLiveAvatarThumbnail')
    s.text(410,433,'Choose a view',20,weight=700)
    s.button('GraphicsHeadshotView',362,448,190,46,'Headshot','blue','avatar',20,26)
    s.button('GraphicsBustView',563,448,188,46,'Bust','plain','avatar',20,26)
    s.button('GraphicsFullBodyView',762,448,189,46,'Full body','plain','body',19,28)
    s.text(410,530,'Describe your graphic',20,weight=700)
    s.panel('GraphicsPromptField',361,546,592,72,'url(#v2-field)','#588abe',14,1.8)
    s.text(374,574,'A neon poster of my avatar, electric blue lighting...',20,'#92a8cd',extra='data-role="EditablePrompt"')
    s.text(939,608,'0/500',15,'#9caecc',anchor='end',extra='data-role="LivePromptCount"')
    s.button('GraphicsAdvancedOptions',362,628,591,36,'Advanced options','plain','gear',17,23,align='left')
    s.icon('chevron',914,637,21,asset='GraphicsAdvancedChevron')
    s.button('GraphicsGenerate',87,678,868,56,'Create graphic · R$ 29','purple','star',25,33,action='BeginAvatarGraphicGeneration')
    s.icon('info',375,744,20,asset='GraphicsPriceConfirmationIcon')
    s.text(403,760,'Confirm in Roblox before paying.',16)
    s.panel('GraphicsActivity',77,775,889,116,'url(#v2-field)','#7060a4',17)
    s.icon('clock',93,786,24,asset='GraphicsActivityClock')
    s.text(133,800,'Latest creation activity',20,weight=700)
    s.panel('GraphicsJobRow',131,811,819,79,'#112547','#344c80',13)
    s.panel('GraphicsJobThumbBackground',136,816,82,68,'#194777','#6e9ec5',9,1)
    s.art('GraphicsJobThumbArt','ReplaceWithLiveGraphicJobThumbnail')
    s.text(235,834,'Generating...',17,weight=700,extra='data-role="LiveGraphicJobStatus"')
    s.text(235,855,'Creating your avatar graphic. This may take a few seconds.',14,'#9cb3d9',extra='data-role="LiveGraphicJobMessage"')
    s.panel('GraphicsProgressTrack',236,863,620,18,'#091a32','#486893',8,1)
    s.parts.append('<g id="GraphicsProgressFill" data-component="progress" data-role="LiveGraphicJobProgress"><rect x="237" y="864" width="390" height="16" rx="8" fill="url(#v2-purple)" stroke="#da80ff"/></g>')
    s.text(866,878,'64%',17,weight=700,extra='data-role="LiveGraphicJobPercent"')
    s.panel('GraphicsGallery',995,229,624,666,'url(#v2-gold-panel)','#ffe55e',24,2.5)
    s.parts.append('<path d="M1245 231h260l-115 82h-200Z" fill="#ffd561" opacity=".07"/>')
    s.icon('picture',1026,254,41,'#ffe577','GraphicsGalleryIcon')
    s.text(1084,291,'Your Gallery',45,weight=900,width=279,shadow=True)
    s.text(1598,286,'2 items',21,anchor='end',extra='data-role="LiveGraphicsGalleryCount"')
    for i,(x,name,when,art) in enumerate([(1007,'Neon Legend','Created 2 minutes ago','GraphicsNeonPosterArt'),(1313,'Purple Vibes','Created 3 days ago','GraphicsPurplePosterArt')]):
        prefix=f'GraphicGalleryCard{i+1}'
        s.panel(prefix,x,319,296,526,'#704000','#b96d0c',16,1.6)
        s.panel(prefix+'PreviewFrame',x+3,326,288,378,'#102949','#35dcff' if i==0 else '#d066fc',14,2)
        s.art(art,'ReplaceWithLiveOwnedGraphicPreview')
        s.text(x+13,730,name,20,weight=700,extra='data-role="LiveOwnedGraphicTitle"')
        s.text(x+13,756,when,17,extra='data-role="LiveOwnedGraphicCreatedTime"')
        s.button(prefix+'CopyLink',x+13,776,174,51,'Copy link','dark','link',17,23,action='CopyFullResolutionGraphicLink')
        s.button(prefix+'Delete',x+197,776,87,51,'Delete','red','trash',15,21,action='DeleteOwnedGraphic')
    s.write('The unsupported download icon controls in the initial image are omitted; Copy link gives access to full resolution. Prices, job progress, avatar and gallery images are replaceable live-data placeholders.')

def games():
    s=Screen('games','Games','Games')
    s.text(80,292,'Play &',85,weight=900,width=279,shadow=True)
    s.text(368,290,'Earn',86,'#06ddff',900,width=226,shadow=True)
    s.icon('star',625,244,41,'#06dfff','GamesHeadingSparkle1');s.icon('star',609,279,21,'#06dfff','GamesHeadingSparkle2')
    s.text(124,323,'Take a break. Find your next challenge.',28,weight=700)
    s.icon('star',82,314,25,'#00cfff','GamesSubtitleSparkle')
    s.button('GamesFreeToPlayBadge',686,261,218,47,'Free to play','dark','game',23,31,action='FreeDestinationsInformation')
    cards=[('Arcade',68,510,'url(#v2-games-blue-panel)','#00ceff','game','11 mini-games. Chase a new best.','GamesArcadeSceneArt','Open Arcade','blue'),('Forge Runway',595,504,'url(#v2-games-purple-panel)','#c963f0','hanger','Style a look. Walk the runway.','GamesRunwaySceneArt','Open Runway','purple'),('Tokens for AFK',1118,497,'url(#v2-games-gold-panel)','#ffdb45','coin','Relax in the lounge. Earn tokens.','GamesLoungeSceneArt','Enter Lounge','gold')]
    for i,(title,x,w,fill,edge,icon,subtitle,art,label,style) in enumerate(cards):
        prefix=f'GamesDestination{i+1}'
        s.panel(prefix,x,339,w,545,fill,edge,26,3)
        s.art(art,'DecorativeDestinationScene')
        s.icon(icon,x+37,359,76 if i==0 else 69,'#ecfcff' if i==0 else '#f088ff' if i==1 else '#ffe982',prefix+'Icon')
        if i==0:
            s.icon('star',469,382,33,'#17ddff',prefix+'BlueStar')
            s.icon('star',525,380,33,'#ffdc45',prefix+'GoldStar')
            s.parts.append('<g id="ArcadeStarRays" data-component="decoration" stroke="#ffe258" stroke-opacity=".7"><path d="M541 370V350M550 377l15-17M554 394l16-3M545 414l4 31M527 410l-7 12" stroke-width="2"/></g>')
        s.text(x+143 if i==0 else x+120 if i==1 else x+112,405,title,59 if i==0 else 52 if i==1 else 48,weight=900,width=[222,351,355][i],shadow=True)
        s.text(x+w/2,445,subtitle,25 if i!=2 else 24,weight=700,anchor='middle')
        s.button(prefix+'Open',x+20,794,w-40,75,label+' ›',style,fs=31,action=['OpenArcade','OpenForgeRunway','EnterAFKTokenLounge'][i])
    s.write('The three illustrated destinations are fixed decorative scenes. All destinations are free. The mini-game count and currency counters are live placeholders.')

def main():
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(trace,JOBS))
    avatar_lab(); avatar_graphics(); games()
    notes={
      'method':'Generated bitmap references measured into native controls and editable SVG text; separate decorative crops converted into genuine vector paths using vtracer. Text headings use native affine width scaling for consistent Arial Black rendering.',
      'traceSettings':{'colors':8,'layerDifference':4,'filterSpeckle':1,'lengthThreshold':2,'excludedControls':'Real SVG evenodd clipping holes retain transparency.'},
      'sourceImages':['mockups/avatar-lab.png','mockups/avatar-graphics.png','mockups/games.png'],
      'outputs':['svg/avatar-lab.svg','svg/avatar-graphics.svg','svg/games.svg'],
      'artworkCrops':[{'source':s,'asset':n,'bounds':b,'excludedControlRects':e} for s,n,b,e in JOBS],
      'intentionalChanges':{'avatar-lab':['Ownership prices use R$.','Card save action is labelled Bookmark; View in Roblox is present.'],'avatar-graphics':['Unsupported standalone download icon buttons omitted; Copy link buttons widened.'],'games':[]},
      'livePlaceholders':'Avatar/catalog/gallery samples, ownership prices, item/creator titles, job state, balances and counts are representative placeholders with data-role tags.',
    }
    (HERE/'avatar-games-conversion.json').write_text(json.dumps(notes,indent=2)+'\n',encoding='utf-8')
    print('Wrote Avatar Lab, Avatar Graphics and Games native SVGs.',flush=True)

if __name__=='__main__': main()
