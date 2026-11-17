"""（開發者用）從 Noto Sans CJK TC 重新產生 data/glyphs/ 的字形資料。

只有在翻譯文字新增了字、或想換字型時才需要執行；一般玩家不需要。

需求：pip install freetype-py scipy numpy pillow
用法：python tools/build_glyphs.py --noto-bold NotoSansCJK-Bold.ttc --noto-medium NotoSansCJK-Medium.ttc

輸出的每張「字形條」接在遊戲原版字型貼圖的正上方（patch.py 負責拼接）。
字形以 SDF（signed distance field）儲存，展開距離＝原版材質的 _GradientScale。
"""
import argparse, collections, json, math, os
from multiprocessing import Pool

import freetype
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, '..', 'data')
SS = 8  # 超取樣倍率

# 字型名稱: (取樣字級 pointSize, SDF 展開＝_GradientScale, 條帶寬度, 條帶最大高度, 使用的字重, 第一列的 y 偏移)
FONTS = {
    'TT_Bluescreens SDF': (100, 6, 6144, 6144 - 1024, 'bold', 7),
    'RobotoBoldCondensed': (44, 17, 4096, 4096 - 1024, 'medium', 18),
}


def is_wanted(ch):
    u = ord(ch)
    if u == 0xB7:
        return True
    if u < 0x2000:              # 拉丁字母等交給原版字型
        return False
    if 0x2460 <= u <= 0x24FF:   # 手把按鍵圖示（遊戲用 IconsFont 顯示）
        return False
    if 0xE000 <= u <= 0xF8FF:   # 私用區（圖示）
        return False
    if u in (0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF):
        return False
    return True


def tc_index(path):
    i = 0
    while True:
        f = freetype.Face(path, i)
        if f.family_name.decode() == 'Noto Sans CJK TC':
            return i
        i += 1


_face = None
def _init(path, idx, pt):
    global _face
    _face = freetype.Face(path, idx)
    _face.set_pixel_sizes(0, pt * SS)


def render(args):
    ch, P = args
    f = _face
    if f.get_char_index(ord(ch)) == 0:
        return ch, None
    f.load_char(ch, freetype.FT_LOAD_NO_HINTING | freetype.FT_LOAD_RENDER)
    m = f.glyph.metrics
    adv = m.horiAdvance / 64 / SS
    if m.width == 0 or m.height == 0:
        return ch, None
    xmin = m.horiBearingX / 64 / SS
    ymax = m.horiBearingY / 64 / SS
    left = math.floor(xmin); right = math.ceil(xmin + m.width / 64 / SS)
    top = math.ceil(ymax); bottom = math.floor(ymax - m.height / 64 / SS)
    w, h = right - left, top - bottom
    W, H = (w + 2 * P) * SS, (h + 2 * P) * SS
    bm = f.glyph.bitmap
    arr = np.array(bm.buffer, dtype=np.uint8).reshape(bm.rows, bm.pitch)[:, :bm.width]
    canvas = np.zeros((H, W), dtype=bool)
    c0 = f.glyph.bitmap_left - (left - P) * SS
    r0 = (top + P) * SS - f.glyph.bitmap_top
    rr0, cc0 = max(r0, 0), max(c0, 0)
    rr1, cc1 = min(r0 + bm.rows, H), min(c0 + bm.width, W)
    canvas[rr0:rr1, cc0:cc1] = arr[rr0 - r0:rr1 - r0, cc0 - c0:cc1 - c0] >= 128
    d = np.where(canvas, distance_transform_edt(canvas) - 0.5, -(distance_transform_edt(~canvas) - 0.5)) / SS
    d = d.reshape(h + 2 * P, SS, w + 2 * P, SS).mean(axis=(1, 3))
    field = np.round(np.clip(0.5 + d / (2 * P), 0, 1) * 255).astype(np.uint8)[::-1]
    return ch, (w, h, float(left), float(top), float(adv), field)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--noto-bold', required=True)
    ap.add_argument('--noto-medium', required=True)
    a = ap.parse_args()

    tr = json.load(open(os.path.join(DATA, 'zh-TW.json'), encoding='utf-8'))
    texts = [v for t in tr['tables'].values() for v in t.values()]
    texts += [tr['locale_name']] + list(tr['language_name_entries'].values())
    cnt = collections.Counter(c for s in texts for c in s)
    required = [c for c, _ in cnt.most_common() if is_wanted(c)]
    for c in '·、。《》「」！（），－：；？':
        if c not in required:
            required.append(c)
    extra = [c for c in open(os.path.join(DATA, 'glyphs', 'extra_chars.txt'), encoding='utf-8').read()
             if is_wanted(c) and c not in set(required)]

    for name, (pt, P, SW, SHMAX, weight, y0) in FONTS.items():
        path = a.noto_bold if weight == 'bold' else a.noto_medium
        with Pool(initializer=_init, initargs=(path, tc_index(path), pt)) as pool:
            res = dict(pool.map(render, [(c, P) for c in required + extra], chunksize=16))
        missing = [c for c in required if res[c] is None]
        if missing:
            raise SystemExit(f'{name}: 字型缺字 {"".join(missing)}')
        strip = np.zeros((SHMAX, SW), dtype=np.uint8)
        gap = 2 * P + 2
        x, y, row_h = P + 1, y0, 0
        glyphs, overflow = [], []
        for c in required + extra:
            r = res[c]
            if r is None:
                continue
            w, h, bx, by, adv, field = r
            if x + w + P + 1 > SW:
                x, y, row_h = P + 1, y + row_h + gap, 0
            if y + h + P + 1 > SHMAX:
                if c in required:
                    overflow.append(c)
                continue
            reg = strip[y - P:y - P + field.shape[0], x - P:x - P + field.shape[1]]
            np.maximum(reg, field, out=reg)
            glyphs.append([ord(c), x, y, w, h, bx, by, adv])
            x += w + gap
            row_h = max(row_h, h)
        if overflow:
            raise SystemExit(f'{name}: 空間不夠，放不下 {len(overflow)} 個必要字')
        sh = int(np.nonzero(strip.any(axis=1))[0].max()) + 1
        Image.fromarray(strip[:sh][::-1]).save(os.path.join(DATA, 'glyphs', name + '.png'), optimize=True)
        json.dump({'font_asset': name, 'padding': P, 'strip_width': SW, 'strip_height': sh,
                   'y_base': 'original_atlas_height',
                   'fields': ['unicode', 'x', 'y', 'w', 'h', 'bearingX', 'bearingY', 'advance'],
                   'glyphs': glyphs},
                  open(os.path.join(DATA, 'glyphs', name + '.json'), 'w'), separators=(',', ':'))
        req_set = set(required)
        print(f'{name}: 必要字 {len(required)}，額外放入 {sum(1 for g in glyphs if chr(g[0]) not in req_set)}，條帶 {SW}x{sh}')


if __name__ == '__main__':
    main()
