#!/usr/bin/env python3
"""ROY MESSANGER uygulama ikonu: SDF ışın yürütme ile gerçek 3B render.

Tuval = Android adaptive icon'un 108dp alanı; u, v ∈ [-1, 1].
Görünür bölge yarıçapı ≈ 0.667 (72dp), güvenli bölge 0.611 (66dp).

Kullanım (numpy + Pillow):
  python3 tool/ikon_ciz.py 1620 /tmp/ikon 2      # ~2 dk, 2x2 örnekleme
  python3 tool/ikon_uret.py /tmp/ikon .          # Android kaynakları + assets
Çıktılar: on.png (RGBA ön katman), arka.png (RGB arka katman),
          tek_renk.png (beyaz + alfa; Android 13 temalı ikon).
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

f32 = np.float32


# ─── küçük yardımcılar ──────────────────────────────────────────────
def normalize(v):
    return v / np.maximum(np.sqrt((v * v).sum(0, keepdims=True)), 1e-12)


def dot(a, b):
    return (a * b).sum(0)


def mix(a, b, t):
    return a * (1 - t) + b * t


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def lin(hexrenk, carp=1.0):
    """'#RRGGBB' (sRGB) → doğrusal ışık uzayı (3,1)."""
    h = hexrenk.lstrip('#')
    c = np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], f32)
    return (c ** 2.2 * carp).reshape(3, 1).astype(f32)


def rot(yaw_deg, pitch_deg, roll_deg=0.0):
    """Yerel → dünya döndürmesi: önce roll (z), sonra yaw (y), sonra pitch (x)."""
    y, p, r = (math.radians(a) for a in (yaw_deg, pitch_deg, roll_deg))
    rz = np.array([[math.cos(r), -math.sin(r), 0], [math.sin(r), math.cos(r), 0], [0, 0, 1]])
    ry = np.array([[math.cos(y), 0, math.sin(y)], [0, 1, 0], [-math.sin(y), 0, math.cos(y)]])
    rx = np.array([[1, 0, 0], [0, math.cos(p), -math.sin(p)], [0, math.sin(p), math.cos(p)]])
    return (rx @ ry @ rz).astype(f32)


# ─── 2B işaretli mesafeler ──────────────────────────────────────────
def sd_rrect(x, y, bx, by, r):
    qx = np.abs(x) - (bx - r)
    qy = np.abs(y) - (by - r)
    return (np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2)
            + np.minimum(np.maximum(qx, qy), 0) - r)


def sd_tri(x, y, p0, p1, p2):
    """iq'nun kesin üçgen mesafesi."""
    (x0, y0), (x1, y1), (x2, y2) = p0, p1, p2
    e = [(x1 - x0, y1 - y0), (x2 - x1, y2 - y1), (x0 - x2, y0 - y2)]
    v = [(x - x0, y - y0), (x - x1, y - y1), (x - x2, y - y2)]
    s = math.copysign(1.0, e[0][0] * e[2][1] - e[0][1] * e[2][0])
    dmin = None
    cmin = None
    for (ex, ey), (vx, vy) in zip(e, v):
        t = np.clip((vx * ex + vy * ey) / (ex * ex + ey * ey), 0, 1)
        dx = vx - ex * t
        dy = vy - ey * t
        d = dx * dx + dy * dy
        c = s * (vx * ey - vy * ex)
        dmin = d if dmin is None else np.minimum(dmin, d)
        cmin = c if cmin is None else np.minimum(cmin, c)
    return -np.sqrt(dmin) * np.sign(cmin)


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


# ─── 3B nesneler ────────────────────────────────────────────────────
class Balon:
    """Yuvarlatılmış kalın levha biçiminde konuşma balonu (kuyruklu)."""

    def __init__(self, merkez, R, bx, by, rc, kuyruk, h, rr, k=0.07,
                 sisirme=0.0):
        self.c = np.asarray(merkez, f32).reshape(3, 1)
        self.R = R
        self.bx, self.by, self.rc = bx, by, rc
        self.kuyruk = kuyruk
        self.h, self.rr, self.k = h, rr, k
        self.sisirme = sisirme

    def yerel(self, p):
        return self.R.T @ (p - self.c)

    def sdf2(self, x, y):
        d = sd_rrect(x, y, self.bx, self.by, self.rc)
        t = sd_tri(x, y, *self.kuyruk) - 0.01
        return smin(d, t, self.k)

    def kabarma(self, x, y):
        """Yüzün yastık gibi kabarması: süperelips (pürüzsüz; mesafe
        alanına bağlı olsaydı orta eksende "X" kırışığı ya da düz plato
        kenarı görünüyordu)."""
        f = np.clip(1 - (x / self.bx) ** 4 - (y / self.by) ** 4, 0, 1)
        return self.sisirme * f * f

    def sdf_yerel(self, l):
        d2 = self.sdf2(l[0], l[1])
        ek = self.kabarma(l[0], l[1])
        wx = d2 + self.rr
        wz = np.abs(l[2]) - (self.h + ek - self.rr)
        return (np.minimum(np.maximum(wx, wz), 0)
                + np.sqrt(np.maximum(wx, 0) ** 2 + np.maximum(wz, 0) ** 2)
                - self.rr)


def sd_elipsoit(l, r):
    k0 = np.sqrt(((l / r) ** 2).sum(0))
    k1 = np.sqrt(((l / (r * r)) ** 2).sum(0))
    return k0 * (k0 - 1) / np.maximum(k1, 1e-9)


# Sahne yerleşimi (dünya birimi = tuval birimi, z kameraya doğru).
ON = Balon(
    merkez=(-0.075, -0.035, 0.12),
    R=rot(-17, -11, 0),
    bx=0.405, by=0.300, rc=0.235,
    kuyruk=((-0.27, -0.08), (-0.345, -0.455), (-0.05, -0.25)),
    h=0.110, rr=0.095, k=0.09, sisirme=0.045,
)
ARKA = Balon(
    merkez=(0.225, 0.245, -0.32),
    R=rot(-17, -11, 0),
    bx=0.335, by=0.250, rc=0.20,
    kuyruk=((0.22, -0.06), (0.295, -0.395), (0.03, -0.20)),
    h=0.085, rr=0.075, k=0.08, sisirme=0.02,
)
NOKTA_R = np.array([0.060, 0.060, 0.030], f32).reshape(3, 1)
NOKTALAR = [np.array([x, 0.012, ON.h + float(ON.kabarma(x, 0.012)) - 0.012],
                     f32).reshape(3, 1)
            for x in (-0.165, 0.0, 0.165)]

M_YOK, M_ON, M_NOKTA, M_ARKA = 0, 1, 2, 3


OLCEK = 0.87


def sahne(p, malzeme=False):
    if malzeme:
        d, m = _sahne(p / OLCEK, True)
        return d * OLCEK, m
    return _sahne(p / OLCEK) * OLCEK


def _sahne(p, malzeme=False):
    lo = ON.yerel(p)
    d_on = ON.sdf_yerel(lo)
    d_n = None
    for c in NOKTALAR:
        dn = sd_elipsoit(lo - c, NOKTA_R)
        d_n = dn if d_n is None else np.minimum(d_n, dn)
    d_arka = ARKA.sdf_yerel(ARKA.yerel(p))
    d = np.minimum(np.minimum(d_on, d_n), d_arka)
    if not malzeme:
        return d
    m = np.full(d.shape, M_ON, np.int8)
    m[d_n <= np.minimum(d_on, d_arka)] = M_NOKTA
    m[d_arka < np.minimum(d_on, d_n)] = M_ARKA
    return d, m


def sahne_sadece_on(p):
    """Gölge ışınları için: ön balon + noktalar."""
    lo = ON.yerel(p / OLCEK)
    d = ON.sdf_yerel(lo)
    for c in NOKTALAR:
        d = np.minimum(d, sd_elipsoit(lo - c, NOKTA_R))
    return d * OLCEK


# ─── ışın yürütme ───────────────────────────────────────────────────
KAMERA_D = 10.0


def yuru(ro, rd, sdf, t0, tmax, adim=160, eps=2.5e-4, guvenlik=0.85):
    n = rd.shape[1]
    t = np.array(t0, f32).copy() if np.ndim(t0) else np.full(n, t0, f32)
    vurdu = np.zeros(n, bool)
    aktif = np.arange(n)
    for _ in range(adim):
        if aktif.size == 0:
            break
        p = ro[:, aktif] + rd[:, aktif] * t[aktif]
        d = sdf(p)
        isabet = d < eps * np.maximum(t[aktif], 1.0)
        vurdu[aktif[isabet]] = True
        t[aktif] += d * guvenlik
        devam = (~isabet) & (t[aktif] < tmax[aktif] if np.ndim(tmax) else t[aktif] < tmax)
        aktif = aktif[devam]
    return t, vurdu


def normal(p, sdf):
    e = 4e-4
    k = np.array([[1, -1, -1], [-1, -1, 1], [-1, 1, -1], [1, 1, 1]], f32)
    n = np.zeros_like(p)
    for kk in k:
        kv = kk.reshape(3, 1)
        n += kv * sdf(p + kv * e)
    return normalize(n)


def yumusak_golge(p, L, sdf, k=10.0, tmax=2.5):
    res = np.ones(p.shape[1], f32)
    t = np.full(p.shape[1], 0.02, f32)
    for _ in range(48):
        h = sdf(p + L * t)
        res = np.minimum(res, np.clip(k * h / t, 0, 1))
        t += np.clip(h, 0.01, 0.2)
        if (t > tmax).all():
            break
    return smoothstep(0, 1, res)


def ortam_kapanma(p, n, sdf):
    occ = np.zeros(p.shape[1], f32)
    sca = 1.0
    for i in range(1, 6):
        h = 0.012 + 0.045 * i
        d = sdf(p + n * h)
        occ += (h - d) * sca
        sca *= 0.72
    return np.clip(1 - 2.2 * occ, 0, 1)


# ─── ışıklar / ortam ────────────────────────────────────────────────
L_ANA = normalize(np.array([-0.55, 0.70, 0.62], f32).reshape(3, 1))
L_DOLGU = normalize(np.array([0.75, -0.25, 0.55], f32).reshape(3, 1))
# Yansımadaki parlak softbox: anahtar ışıktan daha YUKARIDA → düz yüz onu
# yansıtmaz (yüz grileşmez), yalnız üst kenar pahı parlar.
L_KUTU = normalize(np.array([-0.30, 0.90, 0.25], f32).reshape(3, 1))
L_KONTUR = normalize(np.array([0.35, 0.75, -0.55], f32).reshape(3, 1))
C_ANA = np.array([1.00, 0.98, 0.93], f32).reshape(3, 1)
C_DOLGU = np.array([0.55, 0.80, 1.00], f32).reshape(3, 1)
C_KONTUR = np.array([0.85, 1.00, 0.75], f32).reshape(3, 1)


def ortam(dir_):
    """Stüdyo ortamı: üstte yumuşak beyaz softbox, altta koyu zümrüt."""
    y = dir_[1:2]
    x = dir_[0:1]
    ust = np.array([0.95, 1.0, 0.92], f32).reshape(3, 1)
    alt = np.array([0.02, 0.10, 0.06], f32).reshape(3, 1)
    orta = np.array([0.25, 0.45, 0.30], f32).reshape(3, 1)
    c = np.where(y > 0, mix(orta, ust, smoothstep(0.0, 0.85, y)),
                 mix(orta, alt, smoothstep(0.0, 0.6, -y)))
    # sol üstte parlak softbox (yansımada parlak bir pencere)
    kutu = smoothstep(0.70, 0.92, dot(dir_, L_KUTU))[None]
    return c + kutu * 4.5 - 0.12 * smoothstep(0.2, 1.0, x)


def golgele(p, n, rd, m):
    v = -rd
    nv = np.clip(dot(n, v), 0, 1)
    fres = (0.04 + 0.96 * (1 - nv) ** 5)[None]
    r = rd - 2 * dot(rd, n)[None] * n
    env = ortam(r)
    rgb = np.zeros_like(p)
    alfa = np.ones(p.shape[1], f32)

    sdf_tum = sahne
    ao = ortam_kapanma(p, n, sdf_tum)[None]
    gol = yumusak_golge(p + n * 0.003, L_ANA, sdf_tum)[None]

    def isik(L, sar=0.0):
        return np.clip((dot(n, L) + sar) / (1 + sar), 0, 1)[None]

    def parlama(L, us):
        hv = normalize(L + v)
        return (np.clip(dot(n, hv), 0, 1) ** us)[None]

    # — ön balon: neon limon, yumuşak parlak "seramik" yüzey —
    on = m == M_ON
    if on.any():
        yy = p[1:2]
        xx = p[0:1]
        ust = lin('#DDFF73')
        orta = lin('#B6F23A')
        alt = lin('#5FB81C')
        t = np.clip((yy + 0.55) / 0.85, 0, 1)
        taban = np.where(t > 0.5, mix(orta, ust, (t - 0.5) * 2), mix(alt, orta, t * 2))
        taban = taban * (1 - 0.10 * np.clip(xx, 0, 1))
        dif = (isik(L_ANA, 0.35) * gol * C_ANA * 0.80
               + isik(L_DOLGU, 0.2) * C_DOLGU * 0.16)
        amb = (0.20 + 0.16 * n[1:2]) * ao
        alt_sacilma = lin('#7BD81E') * (1 - nv)[None] ** 2 * 0.30
        spec = (parlama(L_ANA, 110) * 0.55 * gol + parlama(L_ANA, 14) * 0.05 * gol
                + parlama(L_DOLGU, 40) * 0.06)
        kontur = isik(L_KONTUR) * (1 - nv)[None] ** 2 * C_KONTUR * 0.35
        c = taban * (amb + dif) + alt_sacilma + spec * C_ANA + kontur
        c = c + fres * env * 0.40 * ao
        rgb[:, on] = c[:, on]

    # — noktalar: koyu, cam gibi parlak —
    nk = m == M_NOKTA
    if nk.any():
        taban = np.array([0.020, 0.065, 0.040], f32).reshape(3, 1)
        dif = isik(L_ANA, 0.2) * gol * 0.35 + 0.08
        spec = parlama(L_ANA, 140) * 1.4 * gol + parlama(L_DOLGU, 60) * 0.25
        c = taban * dif * 3 + spec * C_ANA + fres * env * 0.9
        rgb[:, nk] = c[:, nk]

    # — arka balon: buzlu yeşil cam (yarı saydam) —
    ar = m == M_ARKA
    if ar.any():
        on_golge = yumusak_golge(p + n * 0.003, L_ANA, sahne_sadece_on, k=6.0)[None]
        renk = lin('#3FD89A')
        dif = isik(L_ANA, 0.5) * on_golge * 0.45 + 0.18
        spec = parlama(L_ANA, 90) * 0.9 * on_golge + parlama(L_KONTUR, 30) * 0.20
        kenar = (1 - nv)[None] ** 2.0
        ust_isik = smoothstep(-0.2, 0.5, p[1:2] / OLCEK - 0.1) * 0.10
        c = renk * (dif + ust_isik) * (0.6 + 0.4 * ao) + spec * C_ANA + fres * env * 0.55 \
            + kenar * lin('#B9FFD9') * 0.45
        a = np.clip(0.30 + 0.55 * kenar[0] + 0.6 * spec[0] + ust_isik[0], 0, 0.95)
        rgb[:, ar] = (c * a[None])[:, ar]  # önçarpımlı
        alfa[ar] = a[ar]

    # önçarpımlı (opak yüzeylerde alfa=1)
    opak = ~ar
    rgb[:, opak] = rgb[:, opak] * 1.0
    return rgb, alfa


def ton_esle(c):
    """Yumuşak tepe sıkıştırma (ACES benzeri) + gama."""
    a, b, cc, d, e = 2.51, 0.03, 2.43, 0.59, 0.14
    x = np.clip((c * (a * c + b)) / (c * (cc * c + d) + e), 0, 1)
    return x ** (1 / 2.2)


def render(boyut, ss=2):
    N = boyut * ss
    # piksel merkezleri, v yukarı
    s = (np.arange(N, dtype=f32) + 0.5) / N * 2 - 1
    u, vv = np.meshgrid(s, -s)
    u = u.ravel()
    vv = vv.ravel()
    # sınır kutusu dışını hiç yürütme
    icerde = (np.abs(u) < 0.82) & (np.abs(vv) < 0.82)
    idx = np.nonzero(icerde)[0]
    ro = np.zeros((3, idx.size), f32)
    ro[2] = KAMERA_D
    rd = normalize(np.stack([u[idx], vv[idx], np.full(idx.size, -KAMERA_D, f32)]))
    zmax, zmin = 0.55, -0.75
    t0 = (KAMERA_D - zmax) / -rd[2]
    tmax = (KAMERA_D - zmin) / -rd[2]
    t, vurdu = yuru(ro, rd, sahne, t0, tmax)

    rgb = np.zeros((3, N * N), f32)
    alfa = np.zeros(N * N, f32)
    maske_on = np.zeros(N * N, f32)
    maske_arka = np.zeros(N * N, f32)
    maske_nokta = np.zeros(N * N, f32)

    h = np.nonzero(vurdu)[0]
    p = ro[:, h] + rd[:, h] * t[h]
    d, m = sahne(p, malzeme=True)
    n = normal(p, sahne)
    c, a = golgele(p, n, rd[:, h], m)
    # ton eşleme önçarpımsız renge uygulanır
    duz = c / np.maximum(a, 1e-6)[None]
    duz = ton_esle(duz * 1.15)
    gi = idx[h]
    rgb[:, gi] = duz * a[None]
    alfa[gi] = a
    maske_on[gi] = (m == M_ON) | (m == M_NOKTA)
    maske_arka[gi] = m == M_ARKA
    maske_nokta[gi] = m == M_NOKTA

    def kucult(x):
        x = x.reshape(-1, N, N) if x.ndim == 2 else x.reshape(1, N, N)
        x = x.reshape(x.shape[0], boyut, ss, boyut, ss).mean((2, 4))
        return x

    return (kucult(rgb), kucult(alfa)[0], kucult(maske_on)[0],
            kucult(maske_arka)[0], kucult(maske_nokta)[0])


def bulanik(a, yaricap_px):
    im = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8), 'L')
    im = im.filter(ImageFilter.GaussianBlur(yaricap_px))
    return np.asarray(im, f32) / 255


def kaydir(a, dx_px, dy_px):
    """Görüntüyü sağa dx, aşağı dy piksel kaydırır (boşluk 0)."""
    out = np.zeros_like(a)
    H, W = a.shape
    dx, dy = int(round(dx_px)), int(round(dy_px))
    ys = slice(max(dy, 0), H + min(dy, 0))
    xs = slice(max(dx, 0), W + min(dx, 0))
    ys2 = slice(max(-dy, 0), H + min(-dy, 0))
    xs2 = slice(max(-dx, 0), W + min(-dx, 0))
    out[ys, xs] = a[ys2, xs2]
    return out


def arka_katman(boyut):
    s = (np.arange(boyut, dtype=f32) + 0.5) / boyut * 2 - 1
    u, v = np.meshgrid(s, -s)
    merkez = np.array([0.10, 0.36, 0.20], f32)
    kenar = np.array([0.012, 0.050, 0.030], f32)
    r = np.sqrt((u + 0.30) ** 2 + (v - 0.55) ** 2)
    t = np.clip(r / 1.75, 0, 1) ** 0.85
    c = merkez[:, None, None] * (1 - t) + kenar[:, None, None] * t
    # balonun arkasında yumuşak neon ışıma
    rg = np.sqrt((u - 0.02) ** 2 + (v - 0.02) ** 2)
    isima = np.exp(-(rg / 0.50) ** 2)[None]
    c = c + isima * np.array([0.30, 0.55, 0.08], f32)[:, None, None] * 0.22
    # sağ alttan hafif turkuaz yansıma
    rt = np.sqrt((u - 0.75) ** 2 + (v + 0.80) ** 2)
    c = c + np.exp(-(rt / 0.55) ** 2)[None] * np.array([0.0, 0.20, 0.18], f32)[:, None, None] * 0.35
    c = np.clip(c, 0, 1)
    rgb = np.transpose(c, (1, 2, 0))
    # 8 bitte bantlaşma olmasın: üçgen titreşim
    rng = np.random.default_rng(7)
    dither = (rng.random(rgb.shape, f32) - rng.random(rgb.shape, f32)) / 255
    return np.clip(rgb + dither, 0, 1)


def main():
    boyut = int(sys.argv[1]) if len(sys.argv) > 1 else 360
    klasor = sys.argv[2] if len(sys.argv) > 2 else '.'
    ss = int(sys.argv[3]) if len(sys.argv) > 3 else 2
    os.makedirs(klasor, exist_ok=True)

    rgb, alfa, m_on, m_arka, m_nokta = render(boyut, ss)
    rgb = np.transpose(rgb, (1, 2, 0))

    # yumuşak gölge (zemine düşen): ön balon tam, cam balon yarım
    px = boyut / 2  # 1 tuval birimi kaç piksel
    golge_kaynak = np.clip(m_on + m_arka * 0.45, 0, 1)
    golge = bulanik(kaydir(golge_kaynak, 0.020 * px, 0.060 * px), 0.055 * px) * 0.55
    golge2 = bulanik(kaydir(golge_kaynak, 0.008 * px, 0.022 * px), 0.016 * px) * 0.35
    g = np.clip(golge + golge2 - golge * golge2, 0, 0.8)
    golge_renk = np.array([0.0, 0.03, 0.015], f32)
    # nesneler gölgenin ÜSTÜNDE (önçarpımlı "over")
    out_rgb = rgb + golge_renk * g[..., None] * (1 - alfa[..., None])
    out_a = alfa + g * (1 - alfa)
    duz = out_rgb / np.maximum(out_a[..., None], 1e-6)
    on = np.dstack([np.clip(duz, 0, 1), np.clip(out_a, 0, 1)])
    Image.fromarray((on * 255 + 0.5).astype(np.uint8), 'RGBA').save(
        os.path.join(klasor, 'on.png'))

    arka = arka_katman(boyut)
    Image.fromarray((arka * 255 + 0.5).astype(np.uint8), 'RGB').save(
        os.path.join(klasor, 'arka.png'))

    # temalı ikon: ön balon (noktalar oyuk) + aradan boşlukla ayrılmış cam balon
    bosluk = bulanik(m_on, 0.012 * px) > 0.02
    tek = np.clip(m_on - m_nokta, 0, 1)
    arka_gor = np.clip(m_arka - bosluk, 0, 1) * 0.6
    tek = np.clip(tek + arka_gor, 0, 1)
    tr = np.dstack([np.ones((boyut, boyut, 3), f32), tek])
    Image.fromarray((tr * 255 + 0.5).astype(np.uint8), 'RGBA').save(
        os.path.join(klasor, 'tek_renk.png'))

    # güvenli bölge denetimi
    s = (np.arange(boyut) + 0.5) / boyut * 2 - 1
    U, V = np.meshgrid(s, -s)
    R = np.sqrt(U ** 2 + V ** 2)
    nesne = (m_on + m_arka) > 0.02
    print('nesne en uzak yarıçap: %.3f (güvenli 0.611)' % R[nesne].max())


if __name__ == '__main__':
    main()
