"""Per-segment narration: synth each line, fit it to its segment, then concat.

Needs VOLC_TTS_API_KEY (env or repo-root .env). Uses rc/segXX.mp4 built by roughcut.py.
"""
import os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.expanduser("~/Downloads/开场前-工作区")
RC = f"{WORK}/rc"
VO = f"{WORK}/segvo"
os.makedirs(VO, exist_ok=True)
OUT = os.path.expanduser("~/Downloads/开场前-配音版.mp4")
VOICE = "zh_female_vv_uranus_bigtts"
LEAD, TAIL = 0.2, 0.3

# segment file -> narration (None = no narration)
SEGS = [
    ("seg00", "周一午休，刷到一场拼盘演出。"),
    ("seg01", "阵容里有 Bad Sweetheart。"),
    ("seg02", "好久没去现场了，有点犹豫。"),
    ("seg03", "先把这场加进开场前。贴上链接，阵容就都出来了。"),
    ("seg04", "晚上睡前，戴上耳机。"),
    ("seg05", "找到 Bad Sweetheart 的唱片，"),
    ("seg06", "抽出一张，放进播放机。"),
    ("seg07", None),
    ("seg08", "听着听着，就睡着了。"),
    ("seg09", "第二晚，再听一张。"),
    ("seg10", "第三晚，挑出最喜欢的那首。"),
    ("seg11", "第四晚，我已经能跟着哼了。"),
    ("seg12", "周四深夜，打开了购票页。"),
    ("seg13", "选一张票，就这么定了。"),
    ("seg14", "那就去吧。"),
    ("seg15", "周六，到现场了。"),
    ("seg16", "Bad Sweetheart 上台，第一首就是我每晚在听的那首。"),
    ("seg99", "开场前。睡前听一张，现场就会唱。"),
]


def dur(path):
    return float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                          "-of", "csv=p=0", path]))


def ff(args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *args], check=True)


parts = []
for name, text in SEGS:
    src = f"{RC}/{name}.mp4"
    out = f"{VO}/{name}.mp4"
    seg_len = dur(src)
    if text is None:
        ff(["-i", src, "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-map", "0:v", "-map", "1:a",
            "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", out])
        print(f"{name}  {seg_len:4.1f}s  (no narration)")
        parts.append(out)
        continue
    mp3 = f"{VO}/{name}.mp3"
    if not os.path.exists(mp3):
        subprocess.run([sys.executable, f"{HERE}/volc_v3.py", "seed-tts-2.0", VOICE, text, mp3],
                       check=True, stdout=subprocess.DEVNULL)
    v_len = dur(mp3)
    need = LEAD + v_len + TAIL
    final = max(seg_len, need)
    extra = final - seg_len
    ms = int(LEAD * 1000)
    fc = (f"[0:v]tpad=stop_mode=clone:stop_duration={extra:.3f}[v];"
          f"[0:a]apad=pad_dur={extra:.3f},volume=0[bed];"
          f"[1:a]aresample=48000,aformat=channel_layouts=stereo,adelay={ms}|{ms}[vo];"
          f"[bed][vo]amix=inputs=2:normalize=0:duration=first[a]")
    ff(["-i", src, "-i", mp3, "-filter_complex", fc, "-map", "[v]", "-map", "[a]", "-t", f"{final:.3f}",
        "-c:v", "libx264", "-crf", "19", "-preset", "veryfast", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k", "-ar", "48000", out])
    flag = f"  EXTENDED +{extra:.1f}s" if extra > 0.05 else ""
    print(f"{name}  seg {seg_len:4.1f}s  voice {v_len:4.1f}s  -> {final:4.1f}s{flag}  {text}")
    parts.append(out)

with open(f"{VO}/list.txt", "w") as fh:
    fh.writelines(f"file '{p}'\n" for p in parts)
ff(["-f", "concat", "-safe", "0", "-i", f"{VO}/list.txt", "-c", "copy", OUT])
print("done", OUT, round(dur(OUT), 1))
