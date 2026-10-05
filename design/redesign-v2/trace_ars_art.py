"""Trace separate measured illustrations from the new Arcade/Settings/Runway images."""
from pathlib import Path
import argparse
import subprocess
import sys

HERE=Path(__file__).resolve().parent
JOBS={
    "arcade":[
        ("ArcadeController",(73,238,163,117),[]),
        ("ArcadeCrown",(508,235,70,62),[]),
        ("ArcadeTrophy",(733,243,89,112),[]),
        ("ArcadeCoins1",(858,324,70,34),[]),
        ("ArcadeCoins2",(983,324,70,34),[]),
        ("ArcadeCoins3",(1106,324,70,34),[]),
        ("ArcadeCalendar",(1240,240,88,87),[]),
        ("ArcadeGift",(1527,247,83,90),[]),
        ("ArcadeFlappyBird",(66,384,181,157),[]),
        ("ArcadeDinoRunner",(458,384,182,157),[]),
        ("ArcadeColorSwitch",(848,384,171,157),[]),
        ("ArcadeNeonSnake",(1236,384,179,157),[]),
        ("ArcadeBlockStacker",(66,560,181,153),[]),
        ("ArcadeBrickBreaker",(458,560,182,153),[]),
        ("ArcadeReflexTap",(848,560,171,153),[]),
        ("ArcadePrismMerge",(1236,560,179,153),[]),
        ("ArcadeMeteorRush",(66,731,181,154),[]),
        ("ArcadeSkyHopper",(458,731,182,154),[]),
        ("ArcadeEchoMatch",(848,731,171,154),[]),
        ("ArcadeLeaderboard",(1236,731,179,154),[]),
    ],
    "settings":[
        ("SettingsCreationArt",(72,338,230,194),[]),
        ("SettingsAccessibilityArt",(855,337,216,194),[]),
        ("SettingsAudioArt",(74,560,225,140),[]),
        ("SettingsEquippedArt",(858,559,244,150),[]),
        ("SettingsTrophyArt",(76,738,192,162),[]),
        ("SettingsFirstSparkArt",(295,783,91,75),[]),
        ("SettingsInviteArt",(427,782,99,76),[]),
        ("SettingsCollectorArt",(565,783,96,75),[]),
        ("SettingsProlificArt",(699,782,95,76),[]),
        ("SettingsCommunityArt",(857,738,213,162),[]),
    ],
    "runway":[
        ("RunwayTitleCrown",(61,225,108,110),[]),
        ("RunwayThemeCrown",(796,240,68,74),[]),
        ("RunwayThemeLeftCrystals",(670,226,124,112),[]),
        ("RunwayThemeRightCrystals",(1152,224,82,112),[]),
        ("RunwayTimerCrystals",(1538,224,82,112),[]),
        ("RunwayAvatarStage",(579,349,596,366),[(579,349,198,54),(1017,358,147,74),(1017,438,149,44)]),
        ("RunwayPlayer1",(129,420,81,86),[]),
        ("RunwayPlayer2",(129,530,81,86),[]),
        ("RunwayPlayer3",(129,640,81,86),[]),
        ("RunwayPlayer4",(129,755,81,86),[]),
        ("RunwayWeeklyPlayer1",(1272,414,60,55),[]),
        ("RunwayWeeklyPlayer2",(1272,479,60,56),[]),
        ("RunwayWeeklyPlayer3",(1272,545,60,55),[]),
        ("RunwayWeeklyPlayer4",(1272,610,60,55),[]),
        ("RunwayWeeklyPlayer5",(1272,675,60,54),[]),
        ("RunwayWeeklyRewardArt",(1207,750,166,121),[]),
    ],
}

def main():
    parser=argparse.ArgumentParser();parser.add_argument("screens",nargs="+",choices=list(JOBS));args=parser.parse_args()
    for slug in args.screens:
        for name,bounds,masks in JOBS[slug]:
            output=HERE/"artwork"/(name+".svg")
            command=[sys.executable,str(HERE/"trace_artwork.py"),str(HERE/"mockups"/(slug+".png")),str(output),
                "--crop",",".join(map(str,bounds)),"--name",name,"--colors","8","--layer-difference","4","--speckle","1"]
            # Small player faces need finer outlines than large decorative art.
            if "Player" in name:
                command.extend(["--layer-difference","1","--speckle","0","--length-threshold","0.8","--mode","polygon"])
            for mask in masks:command.extend(["--exclude",",".join(map(str,mask))])
            result=subprocess.run(command,capture_output=True,text=True)
            if result.returncode:raise RuntimeError(result.stderr or result.stdout)
            print(name,flush=True)

if __name__=="__main__":main()
