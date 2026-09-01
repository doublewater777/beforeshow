#!/usr/bin/env python3
from pathlib import Path
import re

root = Path('apps/ios/BeforeShow')
guard_path = Path('apps/ios/scripts/check_architecture.py')

DECL = re.compile(r'^(?:@\w+(?:\([^)]*\))?\s*)*(?:(?:public|internal|private|fileprivate|final|indirect|nonisolated|@MainActor)\s+)*(?:struct|class|enum|protocol|actor|extension)\s+([^\s:{<(]+)')


def top_level_blocks(text: str):
    lines = text.splitlines(keepends=True)
    offsets=[]; running=0
    for line in lines:
        offsets.append(running); running += len(line)
    starts=[]; depth=0; block=False
    for i,line in enumerate(lines):
        if depth == 0 and not block:
            m = DECL.match(line)
            if m:
                starts.append((offsets[i], m.group(1)))
        j=0; string=False; escape=False
        while j < len(line):
            if block:
                end=line.find('*/',j)
                if end < 0: break
                block=False; j=end+2; continue
            if not string and line.startswith('//',j): break
            if not string and line.startswith('/*',j): block=True; j+=2; continue
            ch=line[j]
            if ch=='"' and not escape: string=not string
            if not string:
                if ch=='{': depth += 1
                elif ch=='}': depth -= 1
            escape = ch=='\\' and not escape
            if ch!='\\': escape=False
            j += 1
    blocks=[]
    for idx,(start,name) in enumerate(starts):
        end=starts[idx+1][0] if idx+1<len(starts) else len(text)
        blocks.append({'name':name,'text':text[start:end].strip()})
    return blocks


def promote(chunk: str) -> str:
    chunk = chunk.replace('private struct ', 'struct ', 1)
    chunk = chunk.replace('private enum ', 'enum ', 1)
    return chunk

source = root / 'Features' / 'Footprints' / 'FootprintDetailView.swift'
text = source.read_text()
blocks = top_level_blocks(text)
expected = [
    'FootprintDetailTokens',
    'FootprintMemoryTarget',
    'FootprintPlaybackPolicy',
    'FootprintDetailView',
    'FootprintMemoryTile',
    'FootprintKeepsakeTile',
    'FootprintLocalImage',
]
actual = [block['name'] for block in blocks]
if actual != expected:
    raise SystemExit(f'FootprintDetail inventory changed: {actual!r}')

folder = root / 'Features' / 'Footprints'
(folder / 'FootprintDetailPresentationSupport.swift').write_text(
    'import Foundation\nimport SwiftUI\n\n' + '\n\n'.join(promote(blocks[i]['text']) for i in [0,1,2]) + '\n'
)
source.write_text(
    'import Foundation\nimport SwiftData\nimport SwiftUI\n\n' + blocks[3]['text'] + '\n'
)
(folder / 'FootprintDetailTiles.swift').write_text(
    'import Foundation\nimport SwiftUI\nimport UIKit\n\n' + '\n\n'.join(promote(blocks[i]['text']) for i in [4,5,6]) + '\n'
)

guard = guard_path.read_text()
old = '    "BeforeShow/Features/Footprints/FootprintDetailView.swift": 40_000,\n'
new = (
    '    "BeforeShow/Features/Footprints/FootprintDetailView.swift": 32_000,\n'
    '    "BeforeShow/Features/Footprints/FootprintDetailPresentationSupport.swift": 6_000,\n'
    '    "BeforeShow/Features/Footprints/FootprintDetailTiles.swift": 12_000,\n'
)
if guard.count(old) != 1:
    raise SystemExit('FootprintDetail budget anchor mismatch')
guard = guard.replace(old, new, 1)

const_anchor = 'COMPANION_MODELS_FORBIDDEN_TOKENS = (\n'
constants = (
    'FOOTPRINT_DETAIL_OWNER_FORBIDDEN_TOKENS = (\n'
    '    "enum FootprintDetailTokens",\n'
    '    "struct FootprintMemoryTarget",\n'
    '    "enum FootprintPlaybackPolicy",\n'
    '    "struct FootprintMemoryTile",\n'
    '    "struct FootprintKeepsakeTile",\n'
    '    "struct FootprintLocalImage",\n'
    ')\n\n'
)
if constants not in guard:
    if guard.count(const_anchor) != 1:
        raise SystemExit('FootprintDetail constant anchor mismatch')
    guard = guard.replace(const_anchor, constants + const_anchor, 1)

check_anchor = '    check_forbidden_tokens(\n        "BeforeShow/Features/Companion/CompanionSharingModels.swift",\n'
checks = (
    '    check_forbidden_tokens(\n'
    '        "BeforeShow/Features/Footprints/FootprintDetailView.swift",\n'
    '        FOOTPRINT_DETAIL_OWNER_FORBIDDEN_TOKENS,\n'
    '        "Keep Footprint detail tokens, overlay models, and tile/media presentation outside the page state owner.",\n'
    '        errors,\n'
    '    )\n'
)
if checks not in guard:
    if guard.count(check_anchor) != 1:
        raise SystemExit('FootprintDetail check anchor mismatch')
    guard = guard.replace(check_anchor, checks + check_anchor, 1)

guard_path.write_text(guard)
