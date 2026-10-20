"""豆包语音合成 v3 (API Key auth). Key: env VOLC_TTS_API_KEY, else repo-root .env (gitignored).

python3 volc_v3.py <resource_id> <speaker> <text> <out.mp3>
"""
import base64, json, os, sys, urllib.request, uuid

def api_key():
    if os.environ.get("VOLC_TTS_API_KEY"):
        return os.environ["VOLC_TTS_API_KEY"]
    env = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".env")
    for line in open(env):
        k, _, v = line.strip().partition("=")
        if k == "VOLC_TTS_API_KEY":
            return v.strip().strip('"')
    sys.exit("VOLC_TTS_API_KEY not set (env or .env)")


resource, speaker, text, out = sys.argv[1:5]
body = {
    "user": {"uid": "beforeshow-video"},
    "req_params": {
        "text": text,
        "speaker": speaker,
        "audio_params": {"format": "mp3", "sample_rate": 24000},
    },
}
req = urllib.request.Request(
    "https://openspeech.bytedance.com/api/v3/tts/unidirectional",
    data=json.dumps(body).encode(),
    headers={
        "X-Api-Key": api_key(),
        "X-Api-Resource-Id": resource,
        "X-Api-Request-Id": str(uuid.uuid4()),
        "Content-Type": "application/json",
    },
)
try:
    raw = urllib.request.urlopen(req, timeout=60).read().decode()
except urllib.error.HTTPError as e:
    sys.exit(f"HTTP {e.code}: {e.read().decode()[:300]}")

audio = b""
for line in raw.splitlines():
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)
    if msg.get("data"):
        audio += base64.b64decode(msg["data"])
    code = msg.get("code", 0)
    if code not in (0, 20000000):
        sys.exit(f"TTS error {code}: {msg.get('message')}")
if not audio:
    sys.exit("no audio returned: " + raw[:300])
open(out, "wb").write(audio)
print("ok", out, len(audio))
