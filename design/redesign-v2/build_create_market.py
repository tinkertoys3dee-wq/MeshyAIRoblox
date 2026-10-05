"""Measured SVG reconstruction of the three generated creator/collection/market images.

Only the approved Home backdrop, shell, branding and shared icons are reused.
Screen geometry is measured from the new image mockups; artwork is path-traced
independently and all labels/controls remain editable SVG elements.
"""
from pathlib import Path
from copy import deepcopy
from PIL import ImageFont
import subprocess
import sys
import xml.etree.ElementTree as E

HERE = Path(__file__).resolve().parent
NS = 'http://www.w3.org/2000/svg'
E.register_namespace('', NS)
E.register_namespace('xlink', 'http://www.w3.org/1999/xlink')
HOME = E.parse(HERE.parent / 'home/forge-ugc.svg').getroot()

def node(tag, parent=None, **attrs):
    el = E.Element('{%s}%s' % (NS, tag), {k.rstrip('_').replace('__', '-'):str(v) for k,v in attrs.items() if v is not None})
    if parent is not None: parent.append(el)
    return el

def text(p,x,y,s,size=24,color='#fff',weight=700,anchor='start',width=None):
    el=node('text',p,x=x,y=y,fill=color,font__size=size,font__weight=weight,font__family='Arial, sans-serif',text__anchor=anchor,filter='url(#small-shadow)')
    if width:
        # Native affine text scaling also works in librsvg, whose textLength support varies.
        fontfile='ariblk.ttf' if weight>=900 else ('arialbd.ttf' if weight>=700 else 'arial.ttf')
        font=ImageFont.truetype('C:/Windows/Fonts/'+fontfile,size)
        scale=width/font.getlength(s)
        el.set('x','0');el.set('transform',f'translate({x} 0) scale({scale} 1)')
        el.set('data-editable-width',str(width))
    el.text=s
    return el

def rect(p,x,y,w,h,fill,stroke='#304464',r=18,sw=2):
    return node('rect',p,x=x,y=y,width=w,height=h,rx=r,fill=fill,stroke=stroke,stroke__width=sw)

def path(p,d,fill='none',stroke=None,sw=2,**attrs):
    return node('path',p,d=d,fill=fill,stroke=stroke,stroke__width=sw,stroke__linecap='round',stroke__linejoin='round',**attrs)

def component(p,name,kind,b):
    return node('g',p,id=name,data__component=kind,data__bounds=' '.join(map(str,b)))

def asset(p,name,b):
    return node('g',p,id=name,data__asset=name,data__bounds=' '.join(map(str,b)))

def panel(p,name,b,tone='blue',r=22):
    g=component(p,name,'panel',b);a=asset(g,name+'Surface',b)
    fills={'blue':'url(#v2-blue-panel)','purple':'url(#v2-purple-panel)','dark':'url(#nav-bg)'}
    strokes={'blue':'#008fef','purple':'#b13de7','dark':'#31425f'}
    rect(a,*b,fills[tone],strokes[tone],r)
    x,y,w,h=b;path(a,f'M{x+r} {y+2}H{x+w-r}',stroke='#c8e8ff',sw=1,opacity='.18')
    return g

def icon(p,name,kind,x,y,w=38,h=None,color='#fff'):
    h=h or w;g=component(p,name,'icon',(x,y,w,h));a=asset(g,name+'Artwork',(x,y,w,h))
    if kind in ('home','cube','bag','pad','plus','star','ticket'):
        node('use',a,href='#'+kind+'-icon',x=x,y=y,width=w,height=h)
        return g
    k=node('g',a,transform=f'translate({x} {y}) scale({w/40} {h/40})')
    if kind=='x': path(k,'M10 10L30 30M30 10L10 30',stroke=color,sw=5)
    elif kind=='search': node('circle',k,cx=16,cy=16,r=11,fill='none',stroke=color,stroke__width=3);path(k,'M24 24L35 35',stroke=color,sw=4)
    elif kind=='shirt': path(k,'M9 3L16 0Q20 8 24 0L31 3L40 12L32 21L28 17V39H12V17L8 21L0 12Z',color)
    elif kind=='upload': path(k,'M2 19L20 1L38 19H27V33H13V19Z',color);rect(k,6,35,28,5,color,None,2,0)
    elif kind=='reset': path(k,'M8 10A14 14 0 1 1 4 26M8 10H0V2',stroke=color,sw=4)
    elif kind=='chevron':path(k,'M13 4L27 20L13 36',stroke=color,sw=4)
    elif kind=='heart':path(k,'M20 38Q-5 20 3 7Q12 -1 20 8Q29 -1 37 7Q45 20 20 38Z','url(#v2-heart)')
    elif kind=='robux':path(k,'M20 1L37 11V29L20 39L3 29V11Z',stroke=color,sw=4);path(k,'M14 14H26V26H14Z',stroke=color,sw=4)
    elif kind=='sparkle':path(k,'M20 0L25 15L40 20L25 25L20 40L15 25L0 20L15 15Z',color)
    elif kind=='check':node('circle',k,cx=20,cy=20,r=19,fill='#b1ffcc');path(k,'M10 20L17 27L30 12',stroke='#006639',sw=4)
    elif kind=='info':node('circle',k,cx=20,cy=20,r=17,fill='none',stroke=color,stroke__width=3);path(k,'M20 17V29',stroke=color,sw=3);node('circle',k,cx=20,cy=10,r=2,fill=color)
    elif kind=='mouse':rect(k,8,1,24,38,'none',color,12,2);path(k,'M20 2V15',stroke=color,sw=3)
    return g

def button(p,name,b,label,tone='cyan',size=26,ik=None):
    g=component(p,name,'button',b);a=asset(g,name+'Surface',b)
    fills={'cyan':'url(#blue-button)','purple':'url(#purple-button)','dark':'url(#nav-bg)','gold':'url(#gold-button)','green':'url(#v2-green)'}
    strokes={'cyan':'#00deff','purple':'#c56cff','dark':'#586d9f','gold':'#ffda79','green':'#a8ff65'}
    x,y,w,h=b
    rect(a,*b,fills[tone],strokes[tone],min(22,h/4),2.1)
    if tone in ('cyan','purple'):a.set('filter','url(#'+('cyan-glow' if tone=='cyan' else 'purple-glow')+')')
    path(a,f'M{x+20} {y+3}H{x+w-20}',stroke='#fff',sw=1,opacity='.24')
    cx=x+w/2
    if ik:
        total= len(label)*size*.55+size*1.7
        icon(g,name+'Icon',ik,cx-total/2,y+(h-size*1.25)/2,size*1.25)
        text(g,cx+size*.65,y+h/2+size*.34,label,size,anchor='middle')
    elif label:text(g,cx,y+h/2+size*.34,label,size,anchor='middle')
    return g

def art(p,name,b,role=None):
    source=E.parse(HERE/'artwork'/f'{name}.svg').getroot()
    for child in source:
        if child.tag.endswith('defs'):p.append(deepcopy(child))
    g=deepcopy(next(child for child in source if child.get('data-component')=='artwork'))
    x,y,w,h=b;g.set('transform',f'translate({x} {y})');g.set('data-bounds',f'0 0 {w} {h}')
    # vtracer stacks transparent pixels as black shapes. A real SVG clipping
    # outline removes the masked UI rectangles while preserving all artwork.
    exclusions={
        'CreateHeroV2':[(1046,722,429,94),(1159,835,195,44)],
        'MyItemsHeroV2':[(1423,307,157,112),(1390,522,209,58)],
        'MarketAvatarV2':[(1518,340,98,128),(1518,478,99,143)],
    }.get(name,[])
    if exclusions:
        defs=node('defs',p);clip=node('clipPath',defs,id=name+'CleanClip',clipPathUnits='userSpaceOnUse')
        d=f'M0 0H{w}V{h}H0Z'
        for ex,ey,ew,eh in exclusions:
            a=max(0,ex-x);bb=max(0,ey-y);c=min(w,ex+ew-x);dd=min(h,ey+eh-y)
            if c>a and dd>bb:d+=f'M{a} {bb}H{c}V{dd}H{a}Z'
        path(clip,d,'#fff',clip__rule='evenodd',fill__rule='evenodd')
        g.set('clip-path',f'url(#{name}CleanClip)')
    if role:g.set('data-role',role)
    p.append(g);return g

def trace(slug,name,b):
    out=HERE/'artwork'/f'{name}.svg'
    subprocess.run([sys.executable,str(HERE/'trace_artwork.py'),str(HERE/'mockups'/f'{slug}.png'),str(out),'--crop',','.join(map(str,b)),'--name',name,'--colors','8','--layer-difference','4','--speckle','1','--length-threshold','2'],check=True,stdout=subprocess.DEVNULL)

def trace_scene(slug,name,b,excludes):
    out=HERE/'artwork'/f'{name}.svg'
    args=[sys.executable,str(HERE/'trace_artwork.py'),str(HERE/'mockups'/f'{slug}.png'),str(out),'--crop',','.join(map(str,b)),'--name',name,'--colors','8','--layer-difference','4','--speckle','1','--length-threshold','2']
    for ex in excludes:args.extend(['--exclude',','.join(map(str,ex))])
    subprocess.run(args,check=True,stdout=subprocess.DEVNULL)

def base(slug,title,active):
    r=node('svg',width=1672,height=941,viewBox='0 0 1672 941',role='img',aria__label=title)
    node('title',r).text=title+' — generated image reconstructed as editable vectors'
    node('desc',r).text='Complete screen with separate panels, controls, editable text, and path-traced decorative illustrations. Item names, statistics, balances and creators are sample data. Runtime previews replace the sample artwork.'
    defs=deepcopy(next(c for c in HOME if c.tag.endswith('defs')));r.append(defs)
    for id_,colors in [('v2-blue-panel',['#0e3865','#082345','#061c37']),('v2-purple-panel',['#4b0d80','#321253','#20123c']),('v2-green',['#30cb2f','#008e19','#005612']),('v2-heart',['#ff778c','#ff496f','#ec2454'])]:
        d=node('linearGradient',defs,id=id_,x1=0,y1=0,x2=0,y2=1)
        for offset,c in zip(('0','.45','1'),colors):node('stop',d,offset=offset,stop__color=c)
    d=node('linearGradient',defs,id='v2-title-cyan',x1=0,y1=0,x2=1,y2=0)
    for offset,c in [('0','#fff'),('.35','#fff'),('.72','#a1f4ff'),('1','#20defb')]:node('stop',d,offset=offset,stop__color=c)
    for id_ in ['blurred-city-backdrop','main-dashboard','currency-and-settings','forge-ugc-logo']:
        r.append(deepcopy(next(c for c in HOME if c.get('id')==id_)))
    navwidth=974 if slug in ('create','market') else 985
    nav=component(r,slug+'Navigation','panel',(385,136,navwidth,77));rect(nav,385,136,navwidth,77,'url(#nav-bg)','#29364f',19)
    for i,(s,k,x,tx) in enumerate([('Home','home',445,496),('Create','cube',680,735),('Market','bag',936,983),('Games','pad',1176,1233)]):
        bx,bw=[(386,235),(621,256),(875,251),(1126,244)][i]
        g=component(nav,slug+'Nav'+s,'button',(bx,137,bw,75))
        if active==s:
            a=asset(g,slug+'Nav'+s+'Surface',(bx,137,bw,75));rect(a,bx,137,bw,75,'url(#home-button)','#00daff',18,2.5)
            a.set('filter','url(#cyan-glow)')
        icon(g,slug+'Nav'+s+'Icon',k,x,155,38)
        text(g,tx,184,s,27,'#fff' if active==s else '#bdcdeb')
    shortcut,close=(1388,145,168,61),(1570,149,53,54)
    if slug=='create':shortcut,close=(1372,141,191,69),(1574,142,60,68)
    elif slug=='market':shortcut,close=(1373,142,182,68),(1568,143,62,66)
    button(r,slug+'MyItemsShortcut',shortcut,'My Items','dark',22,'bag' if slug=='create' else 'cube')
    if active=='MyItems':r.find('.//*[@id="'+slug+'MyItemsShortcutSurface"]').find('{'+NS+'}rect').set('stroke','#cb58fa')
    c=button(r,slug+'Close',close,'','dark');icon(c,slug+'CloseIcon','x',close[0]+(close[2]-40)/2,close[1]+(close[3]-40)/2,40)
    return r

def save(r,slug):
    out=HERE/'svg'/f'{slug}.svg';out.parent.mkdir(exist_ok=True)
    E.indent(r,space='  ');E.ElementTree(r).write(out,encoding='utf-8',xml_declaration=True)
    print(out)

def create():
    r=base('create','Create UGC','Create')
    text(r,118,292,'Create UGC',72,weight=900,width=423);text(r,125,329,'Describe it. Wear it.',34,'#b3c6ee')
    for i,(x,y,s) in enumerate([(568,252,38),(43,279,29),(600,295,18)]):icon(r,'CreateTitleSparkle'+str(i),'sparkle',x,y,s,color='#29d7ff')
    left=panel(r,'CreatePromptPanel',(65,351,823,537),'blue',18)
    text(left,90,397,'Tell us your idea',34)
    field=component(left,'CreatePromptInput','input',(88,412,777,111));rect(asset(field,'CreatePromptField',(88,412,777,111)),88,412,777,111,'#153e72','#258fdb',17)
    text(field,110,449,'A crystal crown with glowing blue gems...',24,'#91acd4',400)
    path(field,'M847 514L856 505M851 516L858 509',stroke='#c8d9fc',sw=2)
    text(left,863,551,'0 / 500',21,'#bdcdeb',400,'end')
    text(left,90,565,'Need an idea? Tap one.',25)
    for i,(name,label,tone) in enumerate([('Dragon','Dragon Wings','red'),('Crown','Crystal Crown','cyan'),('Katana','Neon Katana','purple'),('Hat','Steampunk Hat','gold'),('Fairy','Fairy Wings','purple')]):
        x=88+i*158;b=(x,581,145,153)
        g=component(left,'CreateIdea'+name,'button',b)
        colors={'red':('#42171e','#ff386a'),'cyan':('#0b3766','#00eaff'),'purple':('#251248','#b356ff'),'gold':('#4a2b0a','#f5ad18')}
        fill,stroke=colors[tone];rect(asset(g,'CreateIdea'+name+'Surface',b),*b,fill,stroke,17)
        if name=='Crown':g.find('.//*[@data-asset="CreateIdeaCrownSurface"]').set('filter','url(#cyan-glow)')
        art(g,'CreateIdea'+name+'Art',(x+7,589,131,107),'ReplaceWithIdeaThumbnail')
        text(g,x+72.5,719,label,17,anchor='middle',width=122 if len(label)>12 else None)
    button(left,'CreateMakeItem',(83,758,787,90),'Make My Item · R$ 199','cyan',35,'robux')
    text(left,477,872,'Confirm the price in Roblox before paying.',18,'#bdcceb',400,'middle')
    right=panel(r,'CreatePreviewPanel',(901,238,716,651),'purple',20)
    right.find('.//{'+NS+'}rect').set('fill','#191c51');right.find('.//{'+NS+'}rect').set('stroke','#6156df')
    text(right,926,294,'Your next creation',42,weight=900,width=352)
    mode=component(right,'CreateModeSelector','panel',(1315,254,286,55));rect(mode,1315,254,286,55,'url(#nav-bg)','#46589b',20)
    button(mode,'CreateSimple',(1320,256,135,50),'Simple','cyan',24)
    dark=component(mode,'CreateAdvanced','button',(1459,256,140,50));text(dark,1529,289,'Advanced',22,'#c2ceeb',700,'middle')
    art(right,'CreateHeroV2',(902,310,714,576),'ReplaceWithCreationPreview')
    note=panel(right,'CreatePreviewNote',(1049,725,423,87),'dark',22)
    icon(note,'CreateNoteSparkle','sparkle',1102,749,40,color='#84edff')
    text(note,1180,760,'AI creates it.',23);text(note,1180,788,'You make it yours.',23)
    how=component(right,'CreateHowItWorks','button',(1158,835,194,39))
    badge=asset(how,'CreateHelpIcon',(1166,840,29,29));node('circle',badge,cx=1180.5,cy=854.5,r=14.5,fill='url(#cyan-icon)')
    text(how,1181,864,'?',24,'#072d59',900,'middle');text(how,1211,862,'How it works',21,'#83e6ff');icon(how,'CreateHowChevron','chevron',1334,845,19)
    save(r,'create')

def myitems():
    r=base('my-items','My Items','MyItems')
    left=panel(r,'MyItemsCollection',(65,233,561,655),'purple',21)
    text(left,88,289,'My Items',52,weight=900)
    text(left,90,326,'Your creations, ready to wear.',27,'#edf0ff',400)
    text(left,606,327,'4 items',23,'#f5e7ff',400,'end')
    button(left,'MyItemsCreateNew',(446,245,167,53),'Create new','cyan',22)
    rows=[('Crown','Crystal Crown','Hat','Ready to wear','#21ed1c'),('Dragon','Dragon Wings','Back Accessory','Ready to wear','#21ed1c'),('Katana','Neon Katana','Gear','Unpublished','#ffce23'),('Hat','Steampunk Hat','Hat','Unpublished','#ffce23')]
    for i,(key,name,kind,status,color) in enumerate(rows):
        y=346+i*139;g=component(left,'MyItemsRow'+key,'button',(77,y,535,127));rect(asset(g,'MyItemsRow'+key+'Surface',(77,y,535,127)),77,y,535,127,'url(#v2-purple-panel)','#13e9ff' if i==0 else '#59346f',22,3 if i==0 else 2)
        art(g,'MyItems'+key+'Thumbnail',(85,y+8,157,110),'ReplaceWithCollectionThumbnail')
        rect(g,85,y+8,157,110,'none','#a848df' if i==0 else '#775c8d',13)
        text(g,262,y+44,name,30,weight=900,width=270 if len(name)>12 else None)
        text(g,264,y+75,kind,23,'#b6bce1',400)
        node('circle',g,cx=277,cy=y+97,r=9.5,fill=color)
        text(g,299,y+105,status,22,color,400)
        icon(g,'MyItems'+key+'Chevron','chevron',568,y+52,19)
    right=panel(r,'MyItemsPreviewPanel',(648,233,967,655),'blue',24)
    text(right,680,296,'Crystal Crown',52,weight=900,width=346)
    ready=panel(right,'MyItemsReadyBadge',(1052,256,210,43),'dark',11);rect(ready,1052,256,210,43,'#076b3d','#28e672',11)
    icon(ready,'MyItemsReadyCheck','check',1066,263,27);text(ready,1104,284,'Ready to wear',22)
    art(right,'MyItemsHeroV2',(650,307,962,327),'ReplaceWithItemPreview')
    icon(right,'MyItemsRotateMouse','mouse',1460,309,60)
    path(right,'M1470 326Q1406 320 1437 348M1514 326Q1573 330 1538 348',stroke='#a3b5f4',sw=3)
    text(right,1492,410,'Drag to rotate',22,'#fff',400,'middle')
    button(right,'MyItemsResetCamera',(1392,524,204,54),'Reset camera','dark',21,'reset')
    text(right,687,648,'Item Name',20,'#bfcbea',400)
    field=component(right,'MyItemsNameInput','input',(685,653,687,52));rect(asset(field,'MyItemsNameField',(685,653,687,52)),685,653,687,52,'#0b172c','#53688d',14)
    text(field,703,689,'Crystal Crown',24,'#fff',400)
    button(right,'MyItemsSaveName',(1395,635,184,62),'Save name','cyan',24)
    field.set('data-state','Advanced item editing');right.find('.//*[@id="MyItemsSaveName"]').set('data-state','Advanced item editing')
    button(right,'MyItemsEquip',(672,719,435,81),'Equip','cyan',40,'shirt')
    button(right,'MyItemsPublish',(1123,719,467,81),'Publish to Roblox','purple',32,'upload')
    foot=panel(right,'MyItemsAdvancedPanel',(669,817,928,56),'dark',17)
    icon(foot,'MyItemsAdvancedChevron','chevron',695,835,18)
    adv=component(foot,'MyItemsAdvancedOptions','button',(690,822,280,46));text(adv,729,852,'Advanced options',23)
    icon(foot,'MyItemsPublishingInfo','info',1106,832,27,color='#9bb5f7')
    text(foot,1144,852,'Publishing to Roblox is separate. Price will be confirmed first.',16,'#bdcdeb',400,width=429)
    save(r,'my-items')

def market():
    r=base('market','Community Market','Market')
    text(r,75,285,'Community Market',58,'url(#v2-title-cyan)',weight=900,width=502);text(r,76,317,'Find a look. Try it on.',26,'#c4e4ff')
    field=component(r,'MarketSearchInput','input',(592,245,386,67));rect(asset(field,'MarketSearchField',(592,245,386,67)),592,245,386,67,'#0a192f','#6386b4',17)
    icon(field,'MarketSearchIcon','search',609,263,32,color='#bdcff2');text(field,657,287,'Search community creations...',21,'#a5b6d6',400,width=278)
    button(r,'MarketSearch',(986,247,126,65),'Search','cyan',25)
    for i,(key,name,creator,likes,favs) in enumerate([('Crown','Crystal Crown','StarryUGC','12.4K','5.8K'),('Wings','Neon Wings','PixelVibe','8.7K','3.1K'),('Katana','Shadow Katana','VoidMaker','15.2K','6.9K')]):
        x=[65,430,790][i];w=[351,347,332][i]
        g=panel(r,'MarketCard'+key,(x,337,w,534),'purple',23)
        g.set('data-role','ReplaceWithCommunityItem')
        text(g,x+30,386,name,38,weight=900,width=min(w-58,ImageFont.truetype('C:/Windows/Fonts/ariblk.ttf',38).getlength(name)))
        art(g,'Market'+key+'Creator',(x+29,398,49,49),'ReplaceWithCreatorAvatar')
        text(g,x+90,426,'by '+creator,22,weight=400)
        # Creator identity is sample data; decorative verification was deliberately omitted.
        art(g,'Market'+key+'Display',(x+16,447,w-32,252),'ReplaceWithCommunityThumbnail')
        button(g,'MarketTry'+key,(x+15,706,w-29,65),'Try on','purple',27,'shirt')
        button(g,'MarketLike'+key,(x+15,788,(w-40)/2,64),likes,'dark',22,'heart')
        button(g,'MarketFavorite'+key,(x+25+(w-40)/2,788,(w-40)/2,64),favs,'dark',22,'star')
    right=panel(r,'MarketAvatarPanel',(1139,236,484,644),'blue',24)
    text(right,1163,286,'Your Avatar',43,weight=900,width=250)
    button(right,'MarketFreeTryOn',(1439,249,170,49),'Free Try-On','green',21,'shirt')
    art(right,'MarketAvatarV2',(1142,304,479,407),'ReplaceWithPlayerViewport')
    reset=button(right,'MarketResetCamera',(1520,342,94,124),'','dark')
    icon(reset,'MarketResetIcon','reset',1545,359,43);text(reset,1567,426,'Reset',18,anchor='middle');text(reset,1567,447,'Camera',18,anchor='middle')
    rot=panel(right,'MarketRotateHint',(1520,480,94,139),'dark',18)
    icon(rot,'MarketRotateMouse','mouse',1551,510,30);path(rot,'M1567 500V489M1537 529H1548M1589 529H1600',stroke='#dfe8ff',sw=3)
    text(rot,1567,577,'Drag to',18,anchor='middle');text(rot,1567,599,'Rotate',18,anchor='middle')
    wearing=panel(right,'MarketWearingPanel',(1142,714,479,164),'dark',22)
    text(wearing,1162,748,'Wearing (1)',27)
    row=panel(wearing,'MarketWearingItem',(1157,763,450,101),'dark',17)
    art(row,'MarketWearingCrown',(1166,772,95,84),'ReplaceWithEquippedThumbnail')
    rect(row,1166,772,95,84,'none','#564679',12)
    text(row,1279,807,'Crystal Crown',27);text(row,1279,839,'by StarryUGC',22,'#a4b3d3',400)
    remove=button(row,'MarketRemove',(1530,784,63,61),'','dark');icon(remove,'MarketRemoveIcon','x',1541,795,42)
    save(r,'market')

def main():
    jobs=[]
    for i,key in enumerate(['Dragon','Crown','Katana','Hat','Fairy']):jobs.append(('create','CreateIdea'+key+'Art',(95+i*158,589,131,107)))
    for i,key in enumerate(['Crown','Dragon','Katana','Hat']):jobs.append(('my-items','MyItems'+key+'Thumbnail',(85,354+i*139,157,110)))
    for i,key in enumerate(['Crown','Wings','Katana']):
        x=[65,430,790][i];w=[351,347,332][i]
        jobs.append(('market','Market'+key+'Creator',(x+29,398,49,49)))
        jobs.append(('market','Market'+key+'Display',(x+16,447,w-32,252)))
    jobs.append(('market','MarketWearingCrown',(1166,772,95,84)))
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=4) as pool:list(pool.map(lambda args:trace(*args),jobs))
    scenes=[('create','CreateHeroV2',(902,310,714,576),[(1046,722,429,94),(1159,835,195,44)]),
        ('my-items','MyItemsHeroV2',(650,307,962,327),[(1423,307,157,112),(1390,522,209,58)]),
        ('market','MarketAvatarV2',(1142,304,479,407),[(1518,340,98,128),(1518,478,99,143)])]
    with ThreadPoolExecutor(max_workers=3) as pool:list(pool.map(lambda args:trace_scene(*args),scenes))
    create();myitems();market()

if __name__=='__main__':main()
