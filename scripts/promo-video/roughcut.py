import os, subprocess
from PIL import Image, ImageDraw, ImageFont

HOME = os.path.expanduser("~")
V = f"{HOME}/Downloads/开场前-视频"
R = f"{HOME}/Downloads/开场前-录屏"
OUT = f"{HOME}/Downloads/开场前-粗剪.mp4"
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TMP = os.path.expanduser("~/Downloads/开场前-工作区/rc")
os.makedirs(TMP, exist_ok=True)
FONT = "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc"
ICON = f"{REPO}/apps/ios/BeforeShow/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
W, H = 1080, 1920

# (kind, file, start, source_seconds, speed, caption)
SEGMENTS = [
    ("ai", f"{V}/shot01.mp4", 0, 3, 1, None),
    ("rec", f"{R}/shot02_秀动演出页.mp4", 0, 3, 1, None),
    ("ai", f"{V}/shot03.mp4", 1, 3, 1, None),
    ("rec", f"{R}/shot04_添加现场.mp4", 0, 33.5, 4, None),
    ("ai", f"{V}/shot05.mp4", 0, 3.5, 1, None),
    ("rec", f"{R}/shot06_唱片柜.mp4", 0, 6, 2, None),
    ("rec", f"{R}/shot07_取碟装碟.mp4", 0, 4.5, 1, None),
    ("rec", f"{R}/shot08_播放.mp4", 0, 3, 1, None),
    ("ai", f"{V}/shot09_v2.mp4", 0, 4, 1, None),
    ("rec", f"{R}/shot10-11_看曲目换碟.mp4", 0, 4, 2, "周二"),
    ("rec", f"{R}/shot10-11_看曲目换碟.mp4", 7, 8, 2, "周三"),
    ("ai", f"{V}/shot12_v2.mp4", 0, 4, 1, "周四"),
    ("rec", f"{R}/shot14_秀动选票.mp4", 0, 5, 1, None),
    ("rec", f"{R}/shot14_秀动选票.mp4", 5, 4, 1, None),
    ("ai", f"{V}/shot15.mp4", 0, 3.5, 1, "那就去吧。"),
    ("ai", f"{V}/shot16.mp4", 0, 4, 1, None),
    ("ai", f"{V}/shot17-18.mp4", 0, 7, 1, None),
]


def caption_png(text, path):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONT, 58, index=7)
    w = d.textlength(text, font=f)
    x, y = (W - w) / 2, H - 420
    for dx, dy in [(0, 3), (2, 2), (-2, 2)]:
        d.text((x + dx, y + dy), text, font=f, fill=(0, 0, 0, 160))
    d.text((x, y), text, font=f, fill=(255, 255, 255, 240))
    img.save(path)


def end_card(path):
    img = Image.new("RGB", (W, H), (8, 8, 10))
    icon = Image.open(ICON).convert("RGBA").resize((260, 260))
    mask = Image.new("L", (260, 260), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 259, 259), radius=58, fill=255)
    img.paste(icon, ((W - 260) // 2, 700), mask)
    d = ImageDraw.Draw(img)
    for text, size, idx, y, color in [
        ("开场前", 76, 11, 1010, (245, 245, 245)),
        ("睡前听一张，现场就会唱", 44, 3, 1130, (200, 190, 170)),
    ]:
        f = ImageFont.truetype(FONT, size, index=idx)
        w = d.textlength(text, font=f)
        d.text(((W - w) / 2, y), text, font=f, fill=color)
    img.save(path)


def run(args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *args], check=True)


parts = []
for i, (kind, src, start, secs, speed, cap) in enumerate(SEGMENTS):
    out = f"{TMP}/seg{i:02d}.mp4"
    dur = secs / speed
    if kind == "ai":
        vf = f"[0:v]setpts=(PTS-STARTPTS)/{speed},scale={W}:{H},fps=30,setsar=1[v0]"
    else:
        vf = (f"[0:v]setpts=(PTS-STARTPTS)/{speed},fps=30,split[a][b];"
              f"[a]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},boxblur=40:2,eq=brightness=-0.18[bg];"
              f"[b]scale=-2:{H}[fg];[bg][fg]overlay=(W-w)/2:0,setsar=1[v0]")
    inputs = ["-ss", str(start), "-t", str(secs), "-i", src]
    last = "v0"
    if cap:
        png = f"{TMP}/cap{i:02d}.png"
        caption_png(cap, png)
        inputs += ["-i", png]
        vf += f";[v0][1:v]overlay=0:0[v1]"
        last = "v1"
    if kind == "ai":
        af = f"[0:a]atrim=0:{secs},asetpts=PTS-STARTPTS,volume=0.6,aresample=48000,aformat=channel_layouts=stereo[aout]"
        fc = vf + ";" + af
        amap = ["-map", "[aout]"]
    else:
        inputs += ["-f", "lavfi", "-t", str(dur), "-i", "anullsrc=r=48000:cl=stereo"]
        aidx = 2 if cap else 1
        fc = vf
        amap = ["-map", f"{aidx}:a"]
    run([*inputs, "-filter_complex", fc, "-map", f"[{last}]", *amap,
         "-t", str(dur), "-c:v", "libx264", "-crf", "19", "-preset", "veryfast",
         "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", out])
    parts.append(out)
    print("seg", i, round(dur, 2))

png = f"{TMP}/end.png"
end_card(png)
out = f"{TMP}/seg99.mp4"
run(["-loop", "1", "-t", "4.6", "-i", png, "-f", "lavfi", "-t", "4.6", "-i", "anullsrc=r=48000:cl=stereo",
     "-vf", "fps=30,fade=t=in:st=0:d=0.8,setsar=1", "-c:v", "libx264", "-crf", "19", "-preset", "veryfast",
     "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-shortest", out])
parts.append(out)

with open(f"{TMP}/list.txt", "w") as fh:
    for p in parts:
        fh.write(f"file '{p}'\n")
run(["-f", "concat", "-safe", "0", "-i", f"{TMP}/list.txt", "-c", "copy", OUT])
print("done", OUT)
