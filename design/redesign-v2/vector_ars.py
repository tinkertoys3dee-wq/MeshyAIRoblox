"""Native SVG construction utilities for the new Arcade/Runway/Settings mockups.

Geometry is populated only after viewing the newly generated screen references.
Illustrative crops are vector paths; panels, controls and labels remain editable.
"""
from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import html
import re
import xml.etree.ElementTree as ET

NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", NS)
ROOT = Path(__file__).resolve().parent


def el(tag, attrs=None, **kwargs):
    values = dict(attrs or {})
    values.update(kwargs)
    return ET.Element(f"{{{NS}}}{tag}", {key.replace('_', '-'): str(value) for key, value in values.items() if value is not None})


class Screen:
    def __init__(self, slug, title):
        self.slug = slug
        self.root = el("svg", width=1672, height=941, viewBox="0 0 1672 941", role="img", aria_label=title)
        self.root.append(el("title")); self.root[-1].text = title
        self.defs = el("defs"); self.root.append(self.defs)
        self.grad("shell", [(0,"#172b47"),(0.08,"#142239"),(0.7,"#101b31"),(1,"#09172a")])
        self.grad("panel", [(0,"#203753"),(0.4,"#152842"),(1,"#09172a")])
        self.grad("card", [(0,"#283c59"),(0.4,"#172a43"),(1,"#0b182d")])
        self.grad("dark", [(0,"#24384f"),(0.45,"#122339"),(1,"#081628")])
        self.grad("cyan", [(0,"#bbffff"),(0.10,"#61e9ff"),(0.48,"#19beda"),(0.85,"#1195ad"),(1,"#096279")])
        self.grad("purple", [(0,"#ead9ff"),(0.1,"#ad88f2"),(0.50,"#7950c2"),(0.86,"#523298"),(1,"#342163")])
        self.grad("gold", [(0,"#ffffb1"),(0.10,"#ffe47a"),(0.50,"#dfb83f"),(0.87,"#ae8524"),(1,"#71501a")])
        self.grad("neutral", [(0,"#627997"),(0.16,"#3c5374"),(0.55,"#223957"),(1,"#15283e")])
        self.grad("nav", [(0,"#233f5b"),(1,"#0a182e")])
        self.grad("off", [(0,"#112236"),(0.5,"#293d57"),(1,"#506783")])
        self.grad("on", [(0,"#70ffff"),(0.5,"#23c3dc"),(1,"#057786")])
        self.grad("blue", [(0,"#7cffff"),(0.1,"#0bcafa"),(0.6,"#0785f6"),(1,"#015ab5")])
        self.grad("green", [(0,"#b5ffa2"),(0.1,"#31ef53"),(0.6,"#08bc35"),(1,"#067820")])
        self.grad("orange", [(0,"#fff5ae"),(0.1,"#ffd845"),(0.6,"#ffab04"),(1,"#d06b00")])
        self.grad("pink", [(0,"#ffd7e0"),(0.1,"#ff5378"),(0.6,"#ed1544"),(1,"#a20723")])
        self.grad("weeklyGold", [(0,"#ab721c"),(.45,"#73501b"),(1,"#4b3018")],True)
        self.grad("bluePanel", [(0,"#065399"),(0.6,"#053781"),(1,"#093d86")],True)
        self.grad("purplePanel", [(0,"#4c138c"),(0.6,"#381178"),(1,"#321474")],True)
        self.grad("runwayPanel", [(0,"#073769"),(0.6,"#06294b"),(1,"#071b34")])
        self.grad("glass", [(0,"#ffffff",.26),(1,"#ffffff",0)])
        filt=el("filter",id="shadow",x="-30%",y="-50%",width="160%",height="200%")
        filt.append(el("feDropShadow",dx=0,dy=4,stdDeviation=3,flood_color="#000",flood_opacity=.7));self.defs.append(filt)
        tx=el("filter",id="textShadow",x="-20%",y="-50%",width="140%",height="200%")
        tx.append(el("feDropShadow",dx=0,dy=2,stdDeviation=1,flood_color="#000",flood_opacity=.85));self.defs.append(tx)

    def grad(self, name, stops, horizontal=False):
        gradient=el("linearGradient",id=name,x1=0,y1=0,x2=1 if horizontal else 0,y2=0 if horizontal else 1)
        for row in stops:
            gradient.append(el("stop",offset=f"{row[0]*100}%",stop_color=row[1],stop_opacity=row[2] if len(row)>2 else 1))
        self.defs.append(gradient)

    def group(self, name, component, parent=None, bounds=None, asset=None, role=None):
        attrs={"id":name,"data-component":component}
        if bounds: attrs["data-bounds"]=" ".join(map(str,bounds))
        if asset: attrs["data-asset"]=asset
        if role: attrs["data-role"]=role
        g=el("g",attrs);(parent if parent is not None else self.root).append(g);return g

    def rect(self, x,y,w,h,fill,stroke=None,rx=10,sw=1,parent=None,**attrs):
        node=el("rect",x=x,y=y,width=w,height=h,rx=rx,fill=fill,stroke=stroke,stroke_width=sw,**attrs)
        (parent if parent is not None else self.root).append(node);return node

    def path(self, d,fill="none",stroke=None,sw=1,parent=None,**attrs):
        node=el("path",d=d,fill=fill,stroke=stroke,stroke_width=sw,**attrs)
        (parent if parent is not None else self.root).append(node);return node

    def text(self,x,y,value,size=23,fill="#ecf5ff",weight=700,anchor="start",parent=None,**attrs):
        node=el("text",x=x,y=y,fill=fill,font_size=size,font_family="Arial, sans-serif",font_weight=weight,
                text_anchor=anchor,filter="url(#textShadow)",**attrs);node.text=value
        (parent if parent is not None else self.root).append(node);return node

    def panel(self,name,x,y,w,h,kind="panel",stroke="#365573",rx=13,parent=None):
        g=self.group(name,"panel",parent,bounds=(x,y,w,h),asset=name+"Art")
        self.rect(x,y,w,h,f"url(#{kind})",stroke,rx,2,parent=g,filter="url(#shadow)")
        self.rect(x+3,y+3,w-6,h-6,"none","#08111f",max(2,rx-2),1,parent=g)
        self.path(f"M{x+rx} {y+4} H{x+w-rx}",stroke="#84a3be",sw=1,parent=g,opacity=.38)
        return g

    def button(self,name,x,y,w,h,label,kind="cyan",size=23,parent=None):
        g=self.group(name,"button",parent,bounds=(x,y,w,h))
        art=self.group(name+"Art","artwork",g,(x,y,w,h),name+"Art")
        strokes={"cyan":"#74eafa","purple":"#aa87de","gold":"#f7db75","neutral":"#7186a1","dark":"#4e647d"}
        self.rect(x,y,w,h,f"url(#{kind})",strokes.get(kind,"#526d8c"),16,2,parent=art,filter="url(#shadow)")
        self.rect(x+3,y+3,w-6,max(8,h*.38),"url(#glass)",None,13,parent=art,opacity=.35)
        self.path(f"M{x+8} {y+h-4} H{x+w-8}",stroke="#000",sw=1,parent=art,opacity=.28)
        if label:self.text(x+w/2,y+h/2+size*.34,label,size,"#f0fbff" if kind not in {"cyan","gold"} else "#fffef4",800,"middle",g)
        return g

    def circle(self,cx,cy,r,fill,stroke=None,sw=1,parent=None,**attrs):
        node=el("circle",cx=cx,cy=cy,r=r,fill=fill,stroke=stroke,stroke_width=sw,**attrs)
        (parent if parent is not None else self.root).append(node);return node

    def icon(self,name,x,y,size,kind,parent=None,color="#c8e9fa"):
        g=self.group(name,"icon",parent,(x,y,size,size),name)
        q=lambda a:x+a*size;v=lambda a:y+a*size
        if kind=="close":
            self.path(f"M{q(.26)} {v(.26)} L{q(.74)} {v(.74)} M{q(.74)} {v(.26)} L{q(.26)} {v(.74)}",stroke=color,sw=size*.09,parent=g,stroke_linecap="round")
        elif kind=="arrow":
            self.path(f"M{q(.18)} {v(.50)} H{q(.80)} M{q(.58)} {v(.25)} L{q(.83)} {v(.50)} L{q(.58)} {v(.75)}",stroke=color,sw=size*.10,parent=g,stroke_linecap="round",stroke_linejoin="round")
        elif kind=="reset":
            self.path(f"M{q(.22)} {v(.33)} A{size*.31} {size*.31} 0 1 1 {q(.21)} {v(.67)} M{q(.22)} {v(.15)} V{v(.36)} H{q(.43)}",stroke=color,sw=size*.085,parent=g,stroke_linecap="round",stroke_linejoin="round")
        elif kind=="plus":
            self.path(f"M{q(.50)} {v(.22)} V{v(.78)} M{q(.22)} {v(.50)} H{q(.78)}",stroke=color,sw=size*.09,parent=g,stroke_linecap="round")
        elif kind=="check":
            self.path(f"M{q(.17)} {v(.50)} L{q(.40)} {v(.73)} L{q(.83)} {v(.27)}",stroke=color,sw=size*.10,parent=g,stroke_linecap="round",stroke_linejoin="round")
        return g

    def artwork(self,name,x,y,role=None,parent=None):
        path=ROOT/"artwork"/(name+".svg")
        source=ET.parse(path).getroot()
        defs=next((node for node in source if node.tag==f"{{{NS}}}defs"),None)
        if defs is not None:
            for child in defs:self.defs.append(deepcopy(child))
        art=next(node for node in source if node.get("data-asset")==name)
        copy=deepcopy(art);copy.set("transform",f"translate({x} {y})")
        copy.set("data-bounds",f"{x} {y} {source.get('width')} {source.get('height')}")
        if role:copy.set("data-role",role)
        (parent if parent is not None else self.root).append(copy);return copy

    def save(self):
        out=ROOT/"svg"/(self.slug+".svg");out.parent.mkdir(parents=True,exist_ok=True)
        ET.indent(self.root,space="  ")
        ET.ElementTree(self.root).write(out,encoding="utf-8",xml_declaration=True)
        print(out)

    def import_home(self,filename,name,parent=None):
        source=ET.parse(ROOT.parent/"home"/"svg"/filename).getroot()
        prefix=self.slug+"_home_"
        for node in source.iter():
            for key,value in list(node.attrib.items()):
                if key=="id":value=prefix+value
                value=re.sub(r"url\(#([^)]+)\)",lambda m:"url(#"+prefix+m[1]+")",value)
                if key.endswith("href") and value.startswith("#"):value="#"+prefix+value[1:]
                node.set(key,value)
        for child in source:
            if child.tag==f"{{{NS}}}defs":
                if not any(n.get("id")==prefix+"city-sky" for n in self.defs):
                    for definition in child:self.defs.append(deepcopy(definition))
            else:
                # Logo/backdrop exports contain artwork only. IDs remain prefixed.
                copy=deepcopy(child);copy.set("data-component","artwork")
                copy.set("data-asset",name);copy.set("data-bounds","0 0 1672 941" if "Backdrop" in filename else "68 0 320 228")
                (parent if parent is not None else self.root).append(copy)

    def chrome(self, settings=False, shell_bottom=900):
        self.import_home("Backdrop.svg",self.slug+"Backdrop")
        self.panel("MainShell",45,111,1592,shell_bottom-111,"shell","#42617e",34)
        self.path("M67 130 H1609 L1629 145",stroke="#8cb6d0",sw=2,opacity=.2)
        source=ET.parse(ROOT.parent/"home"/"forge-ugc.svg").getroot()
        brand=deepcopy(next(node for node in source if node.get("id")=="forge-ugc-logo"))
        prefix=self.slug+"_home_"
        for node in brand.iter():
            for key,value in list(node.attrib.items()):
                if key=="id":value=prefix+value
                value=re.sub(r"url\(#([^)]+)\)",lambda m:"url(#"+prefix+m[1]+")",value)
                node.set(key,value)
        brand.set("data-component","branding")
        # The original approved brand contains editable vector lettering.
        # Its lettering is not placed in an exportable artwork-only asset.
        self.root.append(brand)
        for name,x,w,value in [("TokenBalance",1144,199,"250"),("PassBalance",1359,193,"12")]:
            self.panel(name,x,30,w,62,"dark","#415371",15)
            self.button(name+"Plus",x+w-54,40,44,42,"","cyan")
            self.icon(name+"PlusIcon",x+w-50,43,37,"plus")
            self.text(x+67,73,value,30,weight=800,data_role="LiveBalance")
        self.import_icon("TokenIcon.svg","HeaderToken",1154,35,47,47)
        self.import_icon("TicketIcon.svg","HeaderPass",1370,37,44,43)
        self.button("HeaderSettings",1572,30,65,64,"","dark")
        self.import_icon("SettingsButton.svg","SettingsGear",1582,40,43,44,content_only=True)
        nav_x=372 if settings else 382
        self.panel("Navigation",nav_x,137,966 if settings else 856,74,"nav","#334964",17)
        specs=[("Home",nav_x+42,nav_x+83),("Create",nav_x+247,nav_x+291),("Market",nav_x+477,nav_x+519),("Games",nav_x+686,nav_x+736)]
        for label,ix,tx in specs:
            if label=="Games" and not settings:self.button("NavGames",1019,139,218,66,"","blue")
            group=self.group("Nav"+label+"Control","button",bounds=(ix-15,142,198,65))
            source={"Home":"NavHome.svg","Create":"NavCreate.svg","Market":"NavMarket.svg","Games":"NavGames.svg"}[label]
            # The approved icon library supplies pure native icon shapes.
            self.import_icon(source,"Nav"+label+"Icon",ix,155,38,37,parent=group,content_only=True)
            self.text(tx,182,label,27,weight=800,parent=group)
        for x in [nav_x+211,nav_x+437,nav_x+643]:self.path(f"M{x} 153 V196",stroke="#53617c",sw=1.3)
        if settings:
            self.button("NavSettings",1243,139,94,71,"","blue")
            self.import_icon("SettingsButton.svg","NavSettingsGear",1268,157,44,42,content_only=True)
            mx,mw,cx=1357,184,1555
        else:mx,mw,cx=1276,247,1544
        self.button("MyItems",mx,139,mw,67,"","dark")
        self.import_icon("NavMarket.svg","MyItemsBag",mx+26,157,38,38,content_only=True)
        self.text(mx+mw*(.66 if settings else .58),182,"My Items",24 if settings else 26,weight=800,anchor="middle")
        self.button("Close",cx,139,69,67,"","dark")
        self.icon("CloseIcon",cx+13,151,44,"close",color="#fcffff")

    def import_icon(self,filename,name,x,y,w,h,parent=None,content_only=False):
        source=ET.parse(ROOT.parent/"home"/"svg"/filename).getroot()
        view=[float(v) for v in source.get("viewBox").split()]
        if content_only and filename.startswith("Nav"):
            view=[12,12,48,48]
        if content_only and filename=="SettingsButton.svg":
            view=[1581,36,48,48]
            for child in list(source):
                if child.tag==f"{{{NS}}}rect":source.remove(child)
        prefix=self.slug+"_"+name+"_"
        for node in source.iter():
            for key,value in list(node.attrib.items()):
                if key=="id":value=prefix+value
                value=re.sub(r"url\(#([^)]+)\)",lambda m:"url(#"+prefix+m[1]+")",value)
                if key.endswith("href") and value.startswith("#"):value="#"+prefix+value[1:]
                node.set(key,value)
        g=self.group(name,"icon",parent,(x,y,w,h),name)
        frame=el("svg",x=x,y=y,width=w,height=h,viewBox=" ".join(map(str,view)))
        g.append(frame)
        for child in source:
            if child.tag==f"{{{NS}}}defs":
                for definition in child:self.defs.append(deepcopy(definition))
            else:frame.append(deepcopy(child))
        return g


def draw_arcade():
    s=Screen("arcade","Forge UGC — Arcade");s.chrome(shell_bottom=900)
    s.panel("ArcadeHeroPanel",65,229,642,140,"bluePanel","#3189fa",19)
    s.artwork("ArcadeController",73,238);s.artwork("ArcadeCrown",508,235)
    s.text(240,305,"Arcade",82,weight=900,stroke="#06102d",stroke_width=6,paint_order="stroke",textLength=274,lengthAdjust="spacingAndGlyphs")
    s.text(241,344,"Quick games. Big personal bests.",29,weight=800)
    s.panel("WeeklyPrizePanel",722,229,487,140,"purplePanel","#b84be7",19)
    s.artwork("ArcadeTrophy",733,243)
    s.text(833,266,"Weekly top 3",28,weight=800)
    for n,cx,value,gradient in [(1,851,"150","gold"),(2,978,"83","neutral"),(3,1103,"33","orange")]:
        g=s.group("WeeklyPrize"+str(n),"icon",bounds=(cx-22,283,44,53),asset="WeeklyMedal"+str(n))
        s.path(f"M{cx} 283 L{cx+22} 296 V320 L{cx} 336 L{cx-22} 320 V296 Z",f"url(#{gradient})","#d8def6",2,g)
        s.text(cx,321,str(n),29,weight=800,anchor="middle")
        s.text(cx+37,314,value,24,weight=800,data_role="WeeklyTokenReward")
        s.artwork("ArcadeCoins"+str(n),[858,983,1106][n-1],324)
    s.panel("DailyChallengePanel",1224,229,388,140,"bluePanel","#39e2eb",19)
    s.artwork("ArcadeCalendar",1240,240);s.artwork("ArcadeGift",1527,247)
    s.text(1338,267,"Daily Challenge",24,weight=800)
    s.text(1338,294,"Score 500 points",20,weight=600,data_role="DailyChallengeInstruction")
    s.text(1338,318,"in any game",20,weight=600,data_role="DailyChallengeInstruction")
    s.rect(1246,336,205,19,"#07142c","#07375c",10)
    s.text(1461,354,"0 / 500",22,weight=800,data_role="DailyChallengeProgress")
    names=["Flappy Bird","Dino Runner","Color Switch","Neon Snake","Block Stacker","Brick Breaker","Reflex Tap","Prism Merge","Meteor Rush","Sky Hopper","Echo Match","Leaderboards"]
    assets=["FlappyBird","DinoRunner","ColorSwitch","NeonSnake","BlockStacker","BrickBreaker","ReflexTap","PrismMerge","MeteorRush","SkyHopper","EchoMatch","Leaderboard"]
    scores=["128","2,384","412","1,920","56","906","0.412s","1,208","3,775","6,520","38",None]
    kinds=["blue","green","purple","orange","purple","orange","cyan","green","blue","purple","orange","blue"]
    strokes=["#28c8fb","#ff987c","#a33fdb","#30a0e9","#8a42ed","#2299fa","#20d6ff","#36e7e1","#814be7","#43a7f8","#7d42dc","#08bfff"]
    tile_colors=[("#067cb5","#075ca3","#063a6e"),("#ec9956","#943c38","#56243d"),("#52138c","#32106f","#29134b"),("#051f44","#0b1641","#081434"),
                 ("#3f117b","#300b65","#291653"),("#06458a","#07448c","#063069"),("#062960","#0a1c53","#0c1644"),("#062b5a","#073861","#062f4d"),
                 ("#35104b","#21154a","#17153b"),("#43b2d9","#0b709e","#064b79"),("#2c1166","#251057","#180c42"),("#063469","#09274f","#092643")]
    lefts=[64,456,846,1234];tops=[382,558,729];widths=[378,376,375,378];heights=[162,158,159]
    for i,name in enumerate(names):
        col,row=i%4,i//4;x,y,w,h=lefts[col],tops[row],widths[col],heights[row]
        s.grad("tileGradient"+str(i),[(0,tile_colors[i][0]),(.5,tile_colors[i][1]),(1,tile_colors[i][2])],True)
        tile=s.panel("ArcadeTile"+assets[i],x,y,w,h,"tileGradient"+str(i),strokes[i],20)
        clip=el("clipPath",id="clip"+assets[i]);clip.append(el("rect",x=x+2,y=y+2,width=w-4,height=h-4,rx=18));s.defs.append(clip)
        art=s.artwork("Arcade"+assets[i],x+2,y+2,role="ReplaceWithGameIllustration")
        s.root.remove(art)
        wrapper=el("g",clip_path="url(#clip"+assets[i]+")");wrapper.append(art);s.root.append(wrapper)
        tx=[261,650,1027,1424][col]
        if i<11:
            s.text(tx,y+40,name,28 if len(name)<12 else 27,weight=800)
            s.text(tx,y+73,"Best: "+scores[i],23,"#b8ddec",700,data_role="LivePersonalBest")
            bx=[257,650,1027,1428][col];by=y+92;bw=[171,168,178,171][col]
            s.button("Play"+assets[i],bx,by,bw,58,"",kinds[i])
            s.text(bx+bw/2-10,by+39,"Play",27,weight=800,anchor="middle")
            s.path(f"M{bx+bw/2+25} {by+18} L{bx+bw/2+39} {by+29} L{bx+bw/2+25} {by+41} Z","#fbffff","#f7ffff",1)
        else:
            s.text(tx,y+36,name,27,weight=800)
            s.text(tx,y+61,"See the top players",19,"#bcd8ea",600)
            s.text(tx,y+84,"and global rankings.",19,"#bcd8ea",600)
            s.button("OpenLeaderboards",1427,826,177,52,"View rankings","blue",20)
    s.save()


def toggle(s,name,x,y,on):
    g=s.group(name,"button",bounds=(x,y,74,35))
    a=s.group(name+"Art","artwork",g,(x,y,74,35),name+"Art")
    s.rect(x,y,74,35,"url(#on)" if on else "url(#off)","#26c4ee" if on else "#72839f",18,2,parent=a)
    s.circle(x+(55 if on else 17),y+17.5,15,"#fbfdff","#c8dcf1",1.5,parent=a,filter="url(#shadow)")


def draw_settings():
    s=Screen("settings","Forge UGC — Settings");s.chrome(settings=True,shell_bottom=932)
    s.text(82,283,"Settings",62,weight=900)
    s.text(86,317,"Make Forge feel right for you.",28,weight=700)
    s.panel("CreationModePanel",65,330,769,208,"bluePanel","#13b7e9",23)
    s.artwork("SettingsCreationArt",72,338)
    s.text(321,372,"Creation mode",32,weight=800)
    s.text(322,400,"Choose the editing experience",22,weight=600)
    s.text(322,424,"that fits your style.",22,weight=600)
    s.button("AdvancedMode",556,443,258,71,"","dark")
    s.import_icon("SettingsButton.svg","AdvancedModeGear",607,459,41,39,content_only=True)
    s.text(713,487,"Advanced",24,"#b5cce6",700,"middle")
    s.button("SimpleMode",322,443,240,71,"","blue")
    s.import_icon("NavCreate.svg","SimpleModeCube",380,458,37,39,content_only=True)
    s.text(474,488,"Simple",24,weight=800,anchor="middle")
    s.panel("AccessibilityPanel",848,328,768,210,"purplePanel","#b44fdf",24)
    s.artwork("SettingsAccessibilityArt",855,337)
    s.text(1083,365,"Accessibility",32,weight=800)
    s.text(1083,394,"Adjust visual options for a more comfortable experience.",20,weight=500)
    for name,y,label,on in [("ReduceMotion",405,"Reduce motion",True),("HighContrast",449,"High contrast",False)]:
        s.rect(1081,y,513,43,"#251345","#683384",18,1)
        s.text(1101,y+28,label,21,weight=700)
        toggle(s,name,1504,y+4,on)
    s.text(1093,523,"UI scale",22,weight=700)
    scale=s.group("InterfaceScale","button",bounds=(1191,501,323,29))
    scale_art=s.group("InterfaceScaleArt","artwork",scale,(1191,501,323,29),"InterfaceScaleArt")
    s.rect(1191,509,322,14,"#1a1934","#7e559b",8,1,parent=scale_art)
    s.rect(1191,509,186,14,"url(#cyan)",None,8,parent=scale_art)
    s.circle(1376,516,16,"#fbfeff","#bed5ee",1.5,parent=scale_art,filter="url(#shadow)")
    s.text(1551,524,"100%",22,weight=800,anchor="middle",data_role="LiveInterfaceScale")
    s.panel("AudioPanel",65,550,769,160,"purplePanel","#b75cdd",22)
    s.artwork("SettingsAudioArt",74,560)
    s.text(322,592,"Audio",31,weight=800)
    s.text(322,621,"Enable or disable game sound effects.",21,weight=500)
    s.rect(322,632,493,53,"#241044","#613387",17,1)
    s.text(340,666,"Sound effects",22,weight=700)
    toggle(s,"SoundEffects",719,639,True)
    s.panel("EquippedItemsPanel",848,550,768,160,"bluePanel","#17c6ec",22)
    s.artwork("SettingsEquippedArt",858,559,role="ReplaceWithEquippedItemThumbnail")
    s.text(1117,594,"Equipped items",31,weight=800)
    s.text(1117,623,"This item shows on your profile and in games.",20,weight=500)
    s.text(1127,674,"Shadow Crown",27,weight=800,data_role="LiveEquippedItemName")
    s.button("RemoveEquipped",1379,638,224,59,"","pink")
    trash=s.group("RemoveTrashIcon","icon",bounds=(1426,650,30,34),asset="RemoveTrashIcon")
    s.rect(1430,660,21,24,"#fff7fa",None,3,parent=trash)
    s.path("M1427 655 H1454 M1435 651 H1448",stroke="#fff7fa",sw=5,parent=trash,stroke_linecap="round")
    s.text(1526,676,"Remove",24,weight=800,anchor="middle")
    s.panel("AchievementsPanel",65,722,769,193,"bluePanel","#0bceee",22)
    s.artwork("SettingsTrophyArt",76,738)
    s.text(287,752,"Achievements",29,weight=800)
    s.text(286,775,"Complete milestones to earn rewards.",19,weight=500)
    for name,x,title,earned in [("FirstSpark",295,"First Spark",True),("Invite",427,"Bring a Friend",False),("Collector",565,"Collector",False),("Prolific",699,"Prolific",True)]:
        s.artwork("Settings"+name+"Art",x,783)
        cx=x+48;s.text(cx,871,title,15,weight=700,anchor="middle",data_role="LiveAchievementName")
        s.rect(cx-56,880,112,28,"url(#gold)" if earned else "url(#dark)","#e0be56" if earned else "#72a0b8",15,1.5)
        s.text(cx+(0 if earned else 9),900,"Earned" if earned else "Locked",17,"#172139" if earned else "#b8d2e9",800,"middle",data_role="LiveAchievementState")
        if not earned:
            g=s.group("AchievementLock"+name,"icon",bounds=(cx-39,884,15,18),asset="AchievementLock"+name)
            s.rect(cx-36,892,11,12,"#adcbe5",None,2,parent=g)
            s.path(f"M{cx-34} 892 V889 A3 3 0 0 1 {cx-27} 889 V892",stroke="#adcbe5",sw=2,parent=g)
    s.panel("CommunityPanel",848,722,768,193,"purplePanel","#b752d6",23)
    s.artwork("SettingsCommunityArt",857,738)
    s.text(1089,762,"Community",31,weight=800)
    s.text(1089,792,"Connect with other creators and grow together.",20,weight=500)
    s.button("InviteFriends",1089,814,239,85,"","blue")
    s.button("JoinCreatorGroup",1343,814,259,85,"","purple")
    for name,x in [("InvitePeople",1110),("JoinPeople",1357)]:
        g=s.group(name,"icon",bounds=(x,833,44,46),asset=name)
        g.append(el("use",href="#settings_home_people-icon",x=x,y=832,width=45,height=48))
    s.icon("InvitePlus",1139,844,25,"plus")
    s.text(1237,867,"Invite friends",23,weight=800,anchor="middle")
    s.text(1489,867,"Join creator group",22,weight=800,anchor="middle")
    s.save()


def crown_icon(s,name,x,y,w=28,h=25):
    g=s.group(name,"icon",bounds=(x,y,w,h),asset=name)
    s.path(f"M{x+2} {y+6} L{x+w*.28} {y+12} L{x+w*.5} {y+1} L{x+w*.72} {y+12} L{x+w-2} {y+6} L{x+w-5} {y+h-3} H{x+5} Z","url(#gold)","#ffef9b",1.4,g)
    s.path(f"M{x+6} {y+h-6} H{x+w-6}",stroke="#ffd456",sw=2,parent=g)
    return g


def draw_runway():
    s=Screen("runway","Forge UGC — Forge Runway");s.chrome(shell_bottom=900)
    s.artwork("RunwayTitleCrown",61,225)
    s.text(171,294,"Forge",65,"#d7f6ff",900,stroke="#03102c",stroke_width=6,paint_order="stroke",font_style="italic",letter_spacing=-2)
    s.text(382,294,"Runway",65,"#c591ff",900,stroke="#280643",stroke_width=6,paint_order="stroke",font_style="italic",letter_spacing=-2)
    s.text(184,332,"Style it. Lock it. Own the stage.",28,"#a9e8ff",800)
    banner=s.group("CurrentThemeBanner","panel",bounds=(744,224,421,109),asset="CurrentThemeBannerArt")
    s.path("M744 224 H1165 L1130 331 H778 Z","url(#purplePanel)","#b141fa",3,banner)
    s.path("M757 232 H1153 L1123 322 H786 Z","none","#8153d2",1.5,banner)
    s.artwork("RunwayThemeLeftCrystals",670,226)
    s.artwork("RunwayThemeRightCrystals",1152,224)
    s.artwork("RunwayThemeCrown",796,240)
    s.text(970,258,"Current Theme",21,"#c7d3eb",600,"middle")
    s.text(998,300,"Cyber Royalty",39,weight=800,anchor="middle",data_role="LiveRunwayTheme")
    s.artwork("RunwayTimerCrystals",1538,224)
    s.button("RunwayPhaseIndicator",1280,234,256,40,"","purple")
    hanger=s.group("PhaseHanger","icon",bounds=(1304,242,31,24),asset="PhaseHanger")
    s.path("M1318 249 Q1326 249 1323 243 Q1321 239 1318 244 M1318 249 L1306 261 H1333 Z",stroke="#f5eaff",sw=2,parent=hanger,stroke_linecap="round",stroke_linejoin="round")
    s.text(1427,261,"STYLING PHASE",21,weight=800,anchor="middle",data_role="LiveRunwayPhase")
    clock=s.group("CountdownClock","icon",bounds=(1345,282,37,40),asset="CountdownClock")
    s.circle(1364,306,16,"none","#f1f7ff",4,parent=clock)
    s.path("M1364 304 V293 M1360 284 H1368 M1364 287 V282",stroke="#f1f7ff",sw=4,parent=clock,stroke_linecap="round")
    s.text(1400,318,"01:24",39,weight=800,data_role="LiveRunwayCountdown")
    s.panel("LineupPanel",61,348,501,534,"runwayPanel","#0ec6fa",19)
    s.text(83,392,"The lineup",33,weight=800)
    s.text(280,391,"(4/4)",26,"#cedcec",800,data_role="LiveEntrantCount")
    player_names=["PixelNova","LunaBlox","ShadowMint","KairoUGC"]
    ys=[412,522,632,747]
    for i,(name,y) in enumerate(zip(player_names,ys),1):
        s.panel("EntrantRow"+str(i),68,y,486,103,"runwayPanel","#0a172a",16)
        color=["orange","neutral","orange","neutral"][i-1]
        s.rect(78,y+25,40,53,"url(#"+color+")","#e5dcab" if i in {1,3} else "#a8b5de",10,2)
        s.text(98,y+64,str(i),36,weight=800,anchor="middle",data_role="LiveEntrantRank")
        py=[420,530,640,755][i-1];s.artwork("RunwayPlayer"+str(i),129,py,role="ReplaceWithPlayerPortrait")
        s.text(231,y+43,name,24,weight=800,data_role="LivePlayerName")
        if i in {2,4}:
            s.circle(246,y+69,15,"#4bea89")
            s.icon("EntrantReady"+str(i),232,y+55,28,"check",color="#06322d")
            s.text(272,y+77,"Ready",22,"#58efa6",800,data_role="LiveEntrantReady")
        else:
            s.circle(247,y+70,13,"none","#074f83",5)
            s.path(f"M247 {y+57} A13 13 0 0 1 260 {y+70}",stroke="#11cdf7",sw=5,stroke_linecap="round")
            s.text(272,y+78,"Styling...",22,"#1bcffa",800,data_role="LiveEntrantReady")
        s.button("ViewLookPlayer"+str(i),383,y+24,161,59,"","blue")
        eye=s.group("ViewLookEye"+str(i),"icon",bounds=(398,y+39,34,29),asset="ViewLookEye"+str(i))
        s.path(f"M400 {y+54} Q414 {y+36} 430 {y+54} Q414 {y+70} 400 {y+54} Z","#e8f8ff",None,1,eye)
        s.circle(415,y+54,7,"#2467ad",None,parent=eye);s.circle(415,y+54,3,"#fff",parent=eye)
        s.text(484,y+63,"View look",20,weight=800,anchor="middle")
    s.panel("AvatarPreviewPanel",577,347,601,536,"runwayPanel","#8649c3",21)
    s.rect(579,349,198,54,"#36216b",None,0)
    s.artwork("RunwayAvatarStage",579,349,role="ReplaceWithLiveAvatarViewport")
    s.text(607,386,"Your look",32,weight=800)
    s.panel("DragInstruction",1017,358,147,74,"dark","#6577ae",17)
    mouse=s.group("RotateMouseIcon","icon",bounds=(1038,373,28,43),asset="RotateMouseIcon")
    s.rect(1041,376,24,39,"none","#e5edfc",12,2,parent=mouse)
    s.path("M1041 393 H1065 M1053 376 V390 M1053 373 V377",stroke="#e5edfc",sw=2,parent=mouse)
    s.text(1080,391,"Drag to",21,"#d4deee",500)
    s.text(1080,414,"rotate",21,"#d4deee",500)
    s.button("ResetCamera",1017,438,149,44,"","dark")
    s.icon("ResetCameraIcon",1028,448,26,"reset",color="#effbff")
    s.text(1108,466,"Reset camera",14,weight=700,anchor="middle")
    s.panel("CreatorXpStrip",593,716,569,39,"dark","#0d1d34",13)
    s.text(610,743,"Runway XP",18,weight=800)
    s.rect(716,728,309,17,"#15253b","#6176a1",10,1.5)
    s.rect(716,728,199,17,"url(#purple)","#b86ae4",10,1.5)
    s.text(1077,743,"320 / 500",18,weight=700,anchor="middle",data_role="LiveCreatorXP")
    crown_icon(s,"CreatorXpCrown",1120,724,25,24)
    s.button("OpenAvatarLab",585,768,151,73,"","blue")
    s.path("M659 787 Q665 786 665 782 Q662 777 659 782 M659 787 L648 798 H674 Z",stroke="#edffff",sw=2,stroke_linejoin="round")
    s.text(661,825,"Open Avatar Lab",17,weight=800,anchor="middle")
    s.button("LockInLook",748,764,260,71,"","purple")
    crown_icon(s,"LockLookCrown",772,782,35,34)
    s.text(901,808,"Lock in my look",27,weight=800,anchor="middle",textLength=166,lengthAdjust="spacingAndGlyphs",data_role="PhaseDependentPrimaryAction")
    s.button("InviteRunwayFriends",1020,768,151,73,"","blue")
    g=s.group("RunwayInvitePeople","icon",bounds=(1080,779,32,27),asset="RunwayInvitePeople")
    g.append(el("use",href="#runway_home_people-icon",x=1080,y=779,width=34,height=29))
    s.text(1095,826,"Invite friends",17,weight=800,anchor="middle")
    s.text(878,868,"Lock in before the timer ends to enter the show!",18,"#b8c9e5",500,"middle",data_role="LivePhaseInstruction")
    s.panel("WeeklyStandingsPanel",1194,348,426,535,"runwayPanel","#1ad1fc",19)
    s.text(1212,388,"Weekly standings",29,weight=800)
    s.button("RefreshWeekly",1478,358,132,42,"","dark")
    s.icon("RefreshWeeklyIcon",1489,366,27,"reset",color="#ebf7ff")
    s.text(1558,386,"Refresh",19,weight=700,anchor="middle")
    weekly=[("RavenStylz","4,890",1), ("PixelNova","4,320",2),("LunaBlox","3,760",3),("KairoUGC","2,910",4),("ShadowMint","2,540",5)]
    for i,(name,score,rank) in enumerate(weekly):
        y=411+i*65.5;kind="weeklyGold" if i==0 else "runwayPanel"
        s.panel("WeeklyRow"+str(rank),1202,y,408,59,kind,"#e6ab26" if i==0 else "#254975",14)
        if rank<=3:
            import math
            points=[]
            for n in range(24):
                r=25 if n%2==0 else 20;a=2*math.pi*n/24-math.pi/2
                points.append((1234+r*math.cos(a),y+29+r*math.sin(a)))
            d="M"+" L".join(f"{px:.2f} {py:.2f}" for px,py in points)+" Z"
            s.path(d,"url(#"+["gold","neutral","orange"][i]+")","#efddc2",1.1)
            s.circle(1234,y+29,16,"none","#f4e5bf",1)
        else:s.rect(1215,y+9,40,45,"url(#neutral)","#849aca",10,1.5)
        s.text(1234,y+39,str(rank),28,weight=800,anchor="middle",data_role="LiveWeeklyRank")
        s.artwork("RunwayWeeklyPlayer"+str(rank),1272,[414,479,545,610,675][i],role="ReplaceWithPlayerPortrait")
        s.text(1351,y+38,name,21,weight=800,data_role="LivePlayerName")
        crown_icon(s,"WeeklyPointCrown"+str(rank),1490,y+18,26,22)
        s.text(1573,y+38,score,20,"#fff389" if i==0 else "#e6f2ff",800,"middle",data_role="LiveWeeklyPoints")
    s.panel("WeeklyCreatorXpPanel",1200,746,415,129,"purplePanel","#ffd94d",17)
    s.artwork("RunwayWeeklyRewardArt",1207,750)
    s.text(1372,786,"Weekly Creator XP",25,weight=800)
    s.text(1376,823,"1st +600 · 2nd +350 · 3rd +200",15,weight=500,data_role="WeeklyCreatorXpRewards")
    s.text(1376,847,"Earn XP in this week's spotlight.",15,weight=500)
    s.save()


if __name__=="__main__":
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument("screens",nargs="+",choices=["arcade","settings","runway"]);args=parser.parse_args()
    for slug in args.screens:
        {"arcade":draw_arcade,"settings":draw_settings,"runway":draw_runway}[slug]()
