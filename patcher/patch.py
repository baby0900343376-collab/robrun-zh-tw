"""ROB RUN 繁體中文化 — 補丁產生器

讀取玩家自己電腦上的「原版」資源檔，產生中文化後的 bundle。
本程式與 data/ 內的資料都不含任何遊戲原始檔案。

用法：
    python patch.py --game-dir "<...>/ROB RUN_Data/StreamingAssets/aa/StandaloneWindows64"
                    --data "<repo>/data" --out "<輸出資料夾>"
"""
import argparse
import json
import os
import sys

import numpy as np
import UnityPy
from PIL import Image

BUNDLES = [
    'inbuild_assets_all.bundle',
    'localization-locales_assets_all.bundle',
    'localization-string-tables-english(unitedstates)(en-us)_assets_all.bundle',
    'localization-string-tables-french(fr)_assets_all.bundle',
    'localization-string-tables-german(de)_assets_all.bundle',
    'localization-string-tables-portuguese(pt)_assets_all.bundle',
    'localization-string-tables-russian(russia)(ru-ru)_assets_all.bundle',
    'localization-string-tables-spanish(es)_assets_all.bundle',
]
INBUILD = BUNDLES[0]
LOCALES = BUNDLES[1]
FONT_ASSETS = ['TT_Bluescreens SDF', 'RobotoBoldCondensed']
GLYPH_INDEX_BASE = 70000


class PatchError(Exception):
    pass


def log(msg):
    print(msg, flush=True)


def save_bundle(env, path):
    data = env.file.save(packer='lz4')
    tmp = path + '.tmp'
    with open(tmp, 'wb') as f:
        f.write(data)
    os.replace(tmp, path)


# ---------------------------------------------------------------- 字串表
def patch_string_tables(env, data, report, name):
    target = data['target_locale_code']
    lang_names = {int(k): v for k, v in data['language_name_entries'].items()}
    tables = {base: {int(k): v for k, v in t.items()} for base, t in data['tables'].items()}
    changed = 0
    for obj in env.objects:
        if obj.type.name != 'MonoBehaviour':
            continue
        tt = obj.read_typetree()
        if 'm_TableData' not in tt or 'm_LocaleId' not in tt:
            continue
        code = tt['m_LocaleId'].get('m_Code', '')
        base = tt['m_Name'].rsplit('_', 1)[0]
        n = 0
        if code == target:
            tr = tables.get(base)
            if tr is None:
                report['warnings'].append(f'{name}: 翻譯資料沒有 {base} 這張表，保留原文')
                continue
            seen = set()
            untranslated = 0
            for e in tt['m_TableData']:
                text = tr.get(int(e['m_Id']))
                seen.add(int(e['m_Id']))
                if text:
                    if e['m_Localized'] != text:
                        e['m_Localized'] = text
                        n += 1
                elif e['m_Localized'].strip():
                    untranslated += 1
            report['tables'][base] = {
                'entries': len(tt['m_TableData']), 'translated': len(tt['m_TableData']) - untranslated,
                'untranslated_in_game': untranslated,
                'unused_translations': len(set(tr) - seen)}
        # 所有語言的「語言名稱」都改成繁體中文
        for e in tt['m_TableData']:
            v = lang_names.get(int(e['m_Id']))
            if v is not None and e['m_Localized'] != v:
                e['m_Localized'] = v
                n += 1
        if n:
            obj.save_typetree(tt)
            changed += n
    return changed


def patch_locales(env, data):
    target = data['target_locale_code']
    hit = 0
    for obj in env.objects:
        if obj.type.name != 'MonoBehaviour':
            continue
        tt = obj.read_typetree()
        if 'm_LocaleName' not in tt:
            continue
        if tt.get('m_Identifier', {}).get('m_Code') == target:
            tt['m_Name'] = data['locale_name']
            tt['m_LocaleName'] = data['locale_name']
            obj.save_typetree(tt)
            hit += 1
    if hit != 1:
        raise PatchError(f'找不到語言代碼 {target} 的 Locale（找到 {hit} 個）')
    return hit


# ---------------------------------------------------------------- 字型
def read_alpha_unity(tex_obj):
    """回傳以 Unity 座標（第 0 列＝最下方）排列的 uint8 alpha 陣列。"""
    tt = tex_obj.read_typetree()
    w, h = tt['m_Width'], tt['m_Height']
    raw = tt.get('image data') or b''
    if tt['m_TextureFormat'] == 1 and len(raw) == w * h:
        return np.frombuffer(raw, dtype=np.uint8).reshape(h, w).copy()
    img = tex_obj.read().image  # 由上到下
    a = np.array(img.convert('RGBA').getchannel('A'), dtype=np.uint8)
    return a[::-1].copy()


def patch_fonts(env, data_dir, report):
    objs = {o.path_id: o for o in env.objects}
    fonts = {}
    for obj in env.objects:
        if obj.type.name == 'MonoBehaviour':
            try:
                name = obj.peek_name()
            except Exception:
                continue
            if name in FONT_ASSETS:
                fonts[name] = obj
    for fname in FONT_ASSETS:
        if fname not in fonts:
            raise PatchError(f'遊戲資源裡找不到字型 {fname}，遊戲版本可能已經改變')
        fobj = fonts[fname]
        ft = fobj.read_typetree()
        meta = json.load(open(os.path.join(data_dir, 'glyphs', fname + '.json'), encoding='utf-8'))
        strip = np.array(Image.open(os.path.join(data_dir, 'glyphs', fname + '.png')).convert('L'))[::-1]
        P = meta['padding']
        cjk_now = sum(1 for c in ft['m_CharacterTable'] if 0x4E00 <= c['m_Unicode'] <= 0x9FFF)
        if cjk_now > 50:
            raise PatchError(f'{fname} 已經含有 {cjk_now} 個中文字，讀到的不是原版檔案')
        if ft.get('m_IsMultiAtlasTexturesEnabled'):
            raise PatchError(f'{fname} 使用多張字型貼圖，目前不支援')
        tex_ref = ft['m_AtlasTextures'][0]
        if tex_ref['m_FileID'] != 0:
            raise PatchError(f'{fname} 的字型貼圖不在同一個檔案裡，目前不支援')
        tobj = objs[tex_ref['m_PathID']]
        orig = read_alpha_unity(tobj)
        oh, ow = orig.shape
        top = max([g['m_GlyphRect']['m_Y'] + g['m_GlyphRect']['m_Height'] for g in ft['m_GlyphTable']] + [0])
        if top + P > oh:
            raise PatchError(f'{fname} 原版貼圖已經用到頂端，無法接上中文字形')
        sh, sw = strip.shape
        W = max(ow, sw)
        H = oh + sh
        H += (-H) % 4
        atlas = np.zeros((H, W), dtype=np.uint8)
        atlas[:oh, :ow] = orig
        atlas[oh:oh + sh, :sw] = strip

        have = {c['m_Unicode'] for c in ft['m_CharacterTable']}
        next_idx = max([g['m_Index'] for g in ft['m_GlyphTable']] + [GLYPH_INDEX_BASE - 1]) + 1
        next_idx = max(next_idx, GLYPH_INDEX_BASE)
        added = 0
        used = list(ft.get('m_UsedGlyphRects', []))
        for u, x, y, w, h, bx, by, adv in meta['glyphs']:
            if u in have:
                continue
            gy = oh + y
            ft['m_GlyphTable'].append({
                'm_Index': next_idx,
                'm_Metrics': {'m_Width': float(w), 'm_Height': float(h), 'm_HorizontalBearingX': float(bx),
                              'm_HorizontalBearingY': float(by), 'm_HorizontalAdvance': float(adv)},
                'm_GlyphRect': {'m_X': x, 'm_Y': gy, 'm_Width': w, 'm_Height': h},
                'm_Scale': 1.0, 'm_AtlasIndex': 0, 'm_ClassDefinitionType': 0})
            ft['m_CharacterTable'].append({'m_ElementType': 1, 'm_Unicode': u, 'm_GlyphIndex': next_idx, 'm_Scale': 1.0})
            used.append({'m_X': x - P, 'm_Y': gy - P, 'm_Width': w + 2 * P, 'm_Height': h + 2 * P})
            next_idx += 1
            added += 1
        ft['m_UsedGlyphRects'] = used
        ft['m_FreeGlyphRects'] = []
        ft['m_AtlasWidth'] = W
        ft['m_AtlasHeight'] = H
        fobj.save_typetree(ft)

        tt = tobj.read_typetree()
        tt['m_Width'], tt['m_Height'] = W, H
        tt['m_TextureFormat'] = 1  # Alpha8
        tt['m_MipCount'] = 1
        tt['m_ImageCount'] = 1
        tt['image data'] = atlas.tobytes()
        tt['m_CompleteImageSize'] = len(tt['image data'])
        tt['m_StreamData'] = {'offset': 0, 'size': 0, 'path': ''}
        tobj.save_typetree(tt)
        report['fonts'][fname] = {'original_atlas': [ow, oh], 'new_atlas': [W, H], 'glyphs_added': added}


# ---------------------------------------------------------------- 主程式
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--game-dir', required=True, help='StandaloneWindows64 資料夾')
    ap.add_argument('--data', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--report', default=None)
    a = ap.parse_args()

    data = json.load(open(os.path.join(a.data, 'zh-TW.json'), encoding='utf-8'))
    os.makedirs(a.out, exist_ok=True)
    report = {'tables': {}, 'fonts': {}, 'warnings': [], 'files': {}}
    try:
        for name in BUNDLES:
            src = os.path.join(a.game_dir, name)
            if not os.path.isfile(src):
                raise PatchError(f'找不到原版檔案：{name}')
            log(f'  · 處理 {name}')
            env = UnityPy.load(src)
            if name == INBUILD:
                patch_fonts(env, a.data, report)
            elif name == LOCALES:
                patch_locales(env, data)
            else:
                patch_string_tables(env, data, report, name)
            dst = os.path.join(a.out, name)
            save_bundle(env, dst)
            report['files'][name] = os.path.getsize(dst)
    except PatchError as e:
        log(f'ERROR: {e}')
        sys.exit(2)
    if a.report:
        with open(a.report, 'w', encoding='utf-8') as f:
            json.dump(report, f, ensure_ascii=False, indent=1)
    for base, r in report['tables'].items():
        log(f'  · {base}: {r["translated"]}/{r["entries"]} 條已翻譯')
        if r['untranslated_in_game']:
            log(f'    （有 {r["untranslated_in_game"]} 條遊戲新文字還沒有翻譯，會顯示原文）')
    for f, r in report['fonts'].items():
        log(f'  · 字型 {f}: 加入 {r["glyphs_added"]} 個字形，貼圖 {r["new_atlas"][0]}x{r["new_atlas"][1]}')
    for w in report['warnings']:
        log(f'  ! {w}')
    log('OK')


if __name__ == '__main__':
    main()
