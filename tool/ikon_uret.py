#!/usr/bin/env python3
"""tool/ikon_ciz.py render'ından Android ikon kaynaklarını ve proje
varlıklarını (assets/icon.png, assets/ikon/*) üretir.

Kullanım: python3 tool/ikon_uret.py <render_klasoru> <proje_koku>
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ikon_ciz import arka_katman  # noqa: E402  (prosedürel arka plan, her boyutta taze titreşim)

kaynak, proje = sys.argv[1], sys.argv[2]
res = os.path.join(proje, 'android/app/src/main/res')

on_ana = Image.open(os.path.join(kaynak, 'on.png')).convert('RGBA')
tek_ana = Image.open(os.path.join(kaynak, 'tek_renk.png')).convert('RGBA')
B = on_ana.size[0]


def kucult(im, boyut):
    """Önçarpımlı alfa ile küçült (saydam kenarda koyu saçak olmasın)."""
    return im.convert('RGBa').resize((boyut, boyut), Image.LANCZOS).convert('RGBA')


def arka(boyut):
    a = arka_katman(boyut)
    return Image.fromarray((a * 255 + 0.5).astype(np.uint8), 'RGB').convert('RGBA')


def kaydet(im, yol):
    os.makedirs(os.path.dirname(yol), exist_ok=True)
    im.save(yol, optimize=True)


# 1) Adaptive katmanlar (108dp tuval)
YOGUNLUK = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
for ad, k in YOGUNLUK.items():
    b = round(108 * k)
    kaydet(kucult(on_ana, b), f'{res}/drawable-{ad}/ic_launcher_foreground.png')
    kaydet(arka(b).convert('RGB'), f'{res}/drawable-{ad}/ic_launcher_background.png')
    kaydet(kucult(tek_ana, b), f'{res}/drawable-{ad}/ic_launcher_monochrome.png')


# 2) Eski Android (7.1 ve öncesi) için tek parça ikonlar
birlesik = Image.alpha_composite(arka(B), on_ana)
kes = round(B * 18 / 108)  # 108dp'nin ortadaki 72dp'si görünür
gorunur = birlesik.crop((kes, kes, B - kes, B - kes))
G = gorunur.size[0]


def sekil_maskesi(boyut, tur, bosluk):
    """4x örneklenmiş, kenarı yumuşak maske. bosluk: kenar payı oranı."""
    S = boyut * 4
    s = (np.arange(S) + 0.5) / S * 2 - 1
    U, V = np.meshgrid(s, s)
    olc = 1 - 2 * bosluk
    U, V = U / olc, V / olc
    if tur == 'daire':
        m = (U ** 2 + V ** 2) <= 1
    else:  # yumuşak köşeli kare (süperelips n=5)
        m = (np.abs(U) ** 5 + np.abs(V) ** 5) <= 1
    im = Image.fromarray(m.astype(np.uint8) * 255, 'L')
    return im.resize((boyut, boyut), Image.LANCZOS)


def tek_parca(boyut, tur, bosluk=0.04):
    # içerik payla birlikte küçülür: görünür bölge maskenin içine sığar
    ic = round(boyut * (1 - 2 * bosluk))
    tuval = Image.new('RGBA', (boyut, boyut), (0, 0, 0, 0))
    tuval.paste(kucult(gorunur, ic), ((boyut - ic) // 2, (boyut - ic) // 2))
    m = sekil_maskesi(boyut, tur, bosluk)
    a = np.asarray(tuval)[..., 3].astype(np.float32) * np.asarray(m, np.float32) / 255
    tuval.putalpha(Image.fromarray(a.round().astype(np.uint8), 'L'))
    return tuval


ESKI = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
for ad, b in ESKI.items():
    kaydet(tek_parca(b, 'kare'), f'{res}/mipmap-{ad}/ic_launcher.png')
    kaydet(tek_parca(b, 'daire'), f'{res}/mipmap-{ad}/ic_launcher_round.png')

# 3) Adaptive XML (flutter_launcher_icons çıktısıyla aynı biçim, inset %0)
XML = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@drawable/ic_launcher_background"/>
  <foreground>
      <inset
          android:drawable="@drawable/ic_launcher_foreground"
          android:inset="0%" />
  </foreground>
  <monochrome>
      <inset
          android:drawable="@drawable/ic_launcher_monochrome"
          android:inset="0%" />
  </monochrome>
</adaptive-icon>
'''
os.makedirs(f'{res}/mipmap-anydpi-v26', exist_ok=True)
for ad in ('ic_launcher', 'ic_launcher_round'):
    with open(f'{res}/mipmap-anydpi-v26/{ad}.xml', 'w', encoding='utf-8') as f:
        f.write(XML)

# 4) Proje varlıkları: flutter_launcher_icons kaynakları + giriş ekranı logosu
varlik = os.path.join(proje, 'assets')
kaydet(tek_parca(1024, 'kare'), f'{varlik}/icon.png')
kaydet(kucult(on_ana, 432), f'{varlik}/ikon/on.png')
kaydet(arka(432).convert('RGB'), f'{varlik}/ikon/arka.png')
kaydet(kucult(tek_ana, 432), f'{varlik}/ikon/tek_renk.png')
kaydet(tek_parca(256, 'kare', bosluk=0.0), f'{varlik}/ikon/logo.png')
print('tamam')
