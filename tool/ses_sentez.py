"""ROY MESSANGER için özgün bildirim ve zil sesleri (tamamen sentez —
lisans/telif yok). Çıktı: <cikti>/wav/*.wav ve <cikti>/ogg/*.ogg

Gerekenler: Python 3 + numpy, libvorbis destekli ffmpeg.
Kullanım:   python tool/ses_sentez.py /tmp/sesler
Sonra:      ogg dosyalarını android/app/src/main/res/raw/ ve assets/sesler/
            altına kopyala (lib/servisler/ses_secenekleri.dart listeler).

Çalgılar: Risset çanı, toplamsal marimba/kalimba, Karplus-Strong telli,
FM "neon" sentezi; her nota yumuşak başlar/biter (tık yok), 25 Hz altı
atılır, bildirimler eşit algılanan yüksekliğe getirilir, konvolüsyon yankısı.
"""
import os
import subprocess
import sys

import numpy as np

SR = 44100
RNG = np.random.default_rng(20261007)


# ---------------------------------------------------------------- yardımcılar
def zaman(sure):
    return np.arange(int(SR * sure)) / SR


def nota(ad):
    """'A4', 'C#5', 'Eb3' → Hz (eşit tamperaman, A4=440)."""
    adlar = {'C': -9, 'D': -7, 'E': -5, 'F': -4, 'G': -2, 'A': 0, 'B': 2}
    harf = ad[0]
    i = 1
    yari = 0
    while i < len(ad) and ad[i] in '#b':
        yari += 1 if ad[i] == '#' else -1
        i += 1
    oktav = int(ad[i:])
    n = adlar[harf] + yari + (oktav - 4) * 12
    return 440.0 * 2 ** (n / 12)


def yumusak_baslangic(x, sure=0.003):
    n = min(len(x), int(SR * sure))
    if n > 0:
        x[:n] *= np.linspace(0, 1, n) ** 2
    return x


def yumusak_bitis(x, sure=0.03):
    n = min(len(x), int(SR * sure))
    if n > 0:
        x[-n:] *= np.cos(np.linspace(0, np.pi / 2, n)) ** 2
    return x


def birakma(x, oran=0.35):
    """Notanın son [oran]'ını kosinüsle söndürür: nota sönmeden kesilince
    oluşan tık sesini önler (doğal bir bırakma gibi)."""
    n = int(len(x) * oran)
    if n > 1:
        x[-n:] *= 0.5 * (1 + np.cos(np.linspace(0, np.pi, n)))
    return x


def yerlestir(iz, sinyal, an, kazanc=1.0):
    bas = int(SR * an)
    son = bas + len(sinyal)
    if son > len(iz):
        iz = np.concatenate([iz, np.zeros(son - len(iz))])
    iz[bas:son] += sinyal * kazanc
    return iz


def alcak_geciren(x, kesim):
    """Tek kutuplu alçak geçiren (vektörel: FFT'de yumuşak eğri)."""
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    H = 1 / np.sqrt(1 + (f / kesim) ** 4)  # 2. derece Butterworth genliği
    return np.fft.irfft(X * H, n)


def yuksek_geciren(x, kesim):
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    H = 1 / np.sqrt(1 + (kesim / np.maximum(f, 1e-6)) ** 4)
    return np.fft.irfft(X * H, n)


def yanki(x, rt60=1.2, karisim=0.22, on_gecikme=0.012, parlaklik=5500):
    """Konvolüsyon yankısı: üstel sönen, alçak geçirilmiş gürültü IR."""
    t = zaman(rt60 * 1.1)
    ir = RNG.standard_normal(len(t)) * np.exp(-6.9 * t / rt60)
    ir = alcak_geciren(ir, parlaklik)
    ir = np.concatenate([np.zeros(int(SR * on_gecikme)), ir])
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    n = len(x) + len(ir) - 1
    N = 1 << (n - 1).bit_length()
    islak = np.fft.irfft(np.fft.rfft(x, N) * np.fft.rfft(ir, N), N)[:n]
    kuru = np.concatenate([x, np.zeros(n - len(x))])
    return kuru * (1 - karisim) + islak * karisim * 1.6


def normalize(x, tepe_db=-1.0):
    x = x - np.mean(x)
    tepe = np.max(np.abs(x)) + 1e-12
    return x / tepe * (10 ** (tepe_db / 20))


# Algılanan yükseklik eşit olsun diye ilk 0.4 sn'nin RMS hedefi (tepe -1 dB
# sınırıyla). "Yumuşak" bilerek daha kısık.
HEDEF_RMS = {'yumusak': 0.09, 'tik': 0.13, 'pit': 0.14}


def esit_yukseklik(x, hedef):
    x = x - np.mean(x)
    bas = x[:int(SR * 0.4)]
    rms = np.sqrt(np.mean(bas ** 2)) + 1e-12
    kazanc = hedef / rms
    tepe_siniri = (10 ** (-1 / 20)) / (np.max(np.abs(x)) + 1e-12)
    return x * min(kazanc, tepe_siniri)


def kirp_sessizlik(x, esik=1e-4, kuyruk=0.05):
    """Sondaki sessizliği at (kuyruk kadar pay bırak)."""
    idx = np.where(np.abs(x) > esik * np.max(np.abs(x)))[0]
    if len(idx) == 0:
        return x
    son = min(len(x), idx[-1] + int(SR * kuyruk))
    return x[:son]


# ------------------------------------------------------------------ çalgılar
def kismi_ton(f, sure, kismiler, atak=0.002):
    """kismiler: [(oran, genlik, sönüm_sn), ...]"""
    t = zaman(sure)
    x = np.zeros_like(t)
    for oran, gen, tau in kismiler:
        if f * oran >= SR / 2 * 0.95:
            continue
        x += gen * np.sin(2 * np.pi * f * oran * t + RNG.uniform(0, 0.3)) * np.exp(-t / tau)
    return birakma(yumusak_baslangic(x, atak))


def marimba(f, sure=1.3, parlak=1.0):
    x = kismi_ton(f, sure, [
        (1.0, 1.0, 0.42),
        (3.93, 0.32 * parlak, 0.075),
        (9.2, 0.10 * parlak, 0.022),
    ], atak=0.0012)
    # tokmak tıkırtısı
    tik = RNG.standard_normal(int(SR * 0.004)) * np.exp(-np.arange(int(SR * 0.004)) / (SR * 0.001))
    tik = alcak_geciren(np.concatenate([tik, np.zeros(200)]), 3000)
    x[:len(tik)] += 0.06 * tik
    return x


def kalimba(f, sure=1.1):
    x = kismi_ton(f, sure, [
        (1.0, 1.0, 0.55),
        (2.0, 0.08, 0.25),
        (5.95, 0.22, 0.045),
    ], atak=0.0008)
    tik = RNG.standard_normal(int(SR * 0.002))
    x[:len(tik)] += 0.02 * tik
    return x


def can(f, sure=2.6, parlak=1.0):
    """Risset çan tarifi (inharmonik kısmiler, farklı sönümler)."""
    tarif = [
        (0.56, 1.0, 1.0), (0.56, 0.67, 0.9), (0.92, 1.0, 0.65),
        (0.92, 1.8, 0.55), (1.19, 2.67, 0.325), (1.70, 1.67, 0.35),
        (2.00, 1.46, 0.25), (2.74, 1.33, 0.2), (3.00, 1.33, 0.15),
        (3.76, 1.0, 0.1), (4.07, 1.33, 0.075),
    ]
    sapma = [0, 1.0, 0, 1.7, 0, 0, 0, 0, 0, 0, 0]
    t = zaman(sure)
    x = np.zeros_like(t)
    for (oran, gen, dur), d in zip(tarif, sapma):
        fr = f * oran + d
        if fr >= SR / 2 * 0.9:
            continue
        g = gen * (parlak if oran > 2 else 1.0)
        x += g * np.sin(2 * np.pi * fr * t) * np.exp(-t / (dur * sure * 0.38))
    return birakma(yumusak_baslangic(x / 6.0, 0.0015))


def kristal(f, sure=1.6):
    t = zaman(sure)
    titres = 1 + 0.0018 * np.sin(2 * np.pi * 5.5 * t)
    x = np.zeros_like(t)
    for oran, gen, tau in [(1, 1.0, 0.9), (2.76, 0.28, 0.35), (5.40, 0.12, 0.14), (8.93, 0.05, 0.06)]:
        faz = 2 * np.pi * f * oran * np.cumsum(titres) / SR
        x += gen * np.sin(faz) * np.exp(-t / tau)
    return birakma(yumusak_baslangic(x, 0.001))


def telli(f, sure=1.6, sonum=0.996, parlaklik=0.5):
    """Karplus-Strong telli (gitar/arp)."""
    n = int(SR * sure)
    p = max(2, int(round(SR / f)))
    tampon = alcak_geciren(RNG.uniform(-1, 1, p * 4), 2500 + 6000 * parlaklik)[:p]
    tampon = tampon - np.mean(tampon)  # DC yok: yoksa uzun, yavaş kayma kalır
    out = np.zeros(n)
    buf = list(tampon)
    idx = 0
    for i in range(n):
        a = buf[idx]
        b = buf[(idx + 1) % p]
        yeni = sonum * 0.5 * (a + b)
        out[i] = a
        buf[idx] = yeni
        idx = (idx + 1) % p
    out = yuksek_geciren(out, 40)
    return birakma(yumusak_baslangic(out, 0.0008), 0.25)


def kare(f, sure, gen=1.0, darbe=0.5):
    """Bant sınırlı kare/darbe dalgası (toplamsal)."""
    t = zaman(sure)
    x = np.zeros_like(t)
    k = 1
    while f * k < SR / 2 * 0.9 and k < 40:
        ak = (2 / (k * np.pi)) * np.sin(k * np.pi * darbe)
        x += ak * np.cos(2 * np.pi * f * k * t)
        k += 1
    return gen * x


def ped(fs, sure, atak=0.5, birak=1.2, sapma=0.004):
    t = zaman(sure)
    x = np.zeros_like(t)
    for f in fs:
        for d in (-sapma, 0, sapma):
            x += np.sin(2 * np.pi * f * (1 + d) * t + RNG.uniform(0, 6.28))
            x += 0.25 * np.sin(2 * np.pi * 2 * f * (1 + d) * t)
    zarf = np.minimum(1, t / atak) * np.minimum(1, np.maximum(0, (sure - t) / birak))
    return alcak_geciren(x * zarf, 2400) / (len(fs) * 3)


def suzme(f0, f1, sure, tau, egri='ustel'):
    """Frekansı f0→f1 kayan sinüs (damla, kuş)."""
    t = zaman(sure)
    if egri == 'ustel':
        fr = f0 * (f1 / f0) ** np.minimum(1, t / sure)
    else:
        fr = f0 + (f1 - f0) * np.minimum(1, t / sure)
    faz = 2 * np.pi * np.cumsum(fr) / SR
    return birakma(yumusak_baslangic(np.sin(faz) * np.exp(-t / tau), 0.002), 0.4)


# ------------------------------------------------------------ bildirim sesleri
def s_kristal():
    iz = np.zeros(1)
    iz = yerlestir(iz, kristal(nota('E6'), 1.5), 0.0, 0.8)
    iz = yerlestir(iz, kristal(nota('B6'), 1.6), 0.11, 0.65)
    return yanki(iz, rt60=1.4, karisim=0.25, parlaklik=7000)


def s_damla():
    iz = np.zeros(1)
    d1 = suzme(620, 1450, 0.10, 0.045)
    d2 = suzme(820, 1900, 0.08, 0.035)
    iz = yerlestir(iz, d1, 0.0, 1.0)
    iz = yerlestir(iz, d2, 0.13, 0.55)
    return yanki(iz, rt60=0.7, karisim=0.18, parlaklik=6000)


def s_pit():
    t = zaman(0.18)
    alt = suzme(240, 110, 0.06, 0.035)
    tik = yuksek_geciren(np.concatenate([RNG.standard_normal(int(SR * 0.003)), np.zeros(400)]), 2000)
    iz = np.zeros(len(t))
    iz = yerlestir(iz, alt, 0.0, 1.0)
    iz = yerlestir(iz, tik * 0.15, 0.0)
    iz = yerlestir(iz, suzme(1100, 1700, 0.05, 0.02) * 0.25, 0.01)
    return yanki(iz, rt60=0.35, karisim=0.12)


def s_marimba():
    iz = np.zeros(1)
    for i, n in enumerate(['C5', 'E5', 'G5']):
        iz = yerlestir(iz, marimba(nota(n), 1.1), i * 0.095, 0.9 - i * 0.1)
    iz = yerlestir(iz, marimba(nota('C6'), 1.2, parlak=0.8), 0.30, 0.55)
    return yanki(iz, rt60=0.9, karisim=0.16)


def s_kampana():
    iz = can(nota('A5'), 2.6)
    return yanki(iz, rt60=1.6, karisim=0.2)


def s_neon():
    iz = np.zeros(1)
    for i, (f0, f1) in enumerate([(520, 1040), (780, 1560)]):
        t = zaman(0.16)
        fr = f0 * (f1 / f0) ** np.minimum(1, t / 0.07)
        faz = 2 * np.pi * np.cumsum(fr) / SR
        indeks = 2.2 * np.exp(-t / 0.05)
        x = np.sin(faz + indeks * np.sin(2 * faz)) * np.exp(-t / 0.06)
        iz = yerlestir(iz, birakma(yumusak_baslangic(x, 0.002)), i * 0.09, 1.0 - i * 0.2)
    return yanki(alcak_geciren(iz, 6000), rt60=0.8, karisim=0.25, parlaklik=8000)


def s_kus():
    iz = np.zeros(1)

    def civilti(f0, f1, sure):
        t = zaman(sure)
        fr = f0 + (f1 - f0) * (t / sure) + 160 * np.sin(2 * np.pi * 38 * t)
        faz = 2 * np.pi * np.cumsum(fr) / SR
        zarf = np.sin(np.pi * np.minimum(1, t / sure)) ** 1.5
        return np.sin(faz) * zarf

    iz = yerlestir(iz, civilti(2900, 4300, 0.075), 0.0, 0.9)
    iz = yerlestir(iz, civilti(3100, 4600, 0.070), 0.11, 0.8)
    iz = yerlestir(iz, civilti(4400, 3000, 0.12), 0.23, 0.6)
    return yanki(iz, rt60=0.9, karisim=0.2, parlaklik=9000)


def s_dingdong():
    iz = np.zeros(1)
    iz = yerlestir(iz, can(nota('E5'), 2.2, parlak=0.6), 0.0, 1.0)
    iz = yerlestir(iz, can(nota('C5'), 2.6, parlak=0.6), 0.42, 1.0)
    return yanki(iz, rt60=1.4, karisim=0.18)


def s_arp():
    iz = np.zeros(1)
    for i, n in enumerate(['C5', 'E5', 'G5', 'C6', 'E6']):
        iz = yerlestir(iz, telli(nota(n), 1.6, sonum=0.997, parlaklik=0.7), i * 0.05, 0.7)
    return yanki(iz, rt60=1.6, karisim=0.3)


def s_kalimba():
    iz = np.zeros(1)
    iz = yerlestir(iz, kalimba(nota('G5'), 1.0), 0.0, 1.0)
    iz = yerlestir(iz, kalimba(nota('D6'), 1.1), 0.14, 0.85)
    return yanki(iz, rt60=0.9, karisim=0.18)


def s_yumusak():
    t = zaman(1.4)
    f = nota('A4')
    x = (np.sin(2 * np.pi * f * t) + 0.18 * np.sin(2 * np.pi * 2 * f * t)
         + 0.06 * np.sin(2 * np.pi * 3 * f * t))
    zarf = np.minimum(1, t / 0.035) * np.exp(-t / 0.45)
    x = birakma(x * zarf)
    y = kismi_ton(nota('E5'), 1.2, [(1, 0.45, 0.4), (2, 0.05, 0.2)], atak=0.03)
    iz = yerlestir(x, y, 0.12)
    return yanki(iz, rt60=1.5, karisim=0.3, parlaklik=4500)


def s_tik():
    t = zaman(0.09)
    x = (np.sin(2 * np.pi * 2100 * t) + 0.4 * np.sin(2 * np.pi * 5200 * t)) * np.exp(-t / 0.012)
    x = birakma(yumusak_baslangic(x, 0.0005))
    return yanki(x, rt60=0.3, karisim=0.1)


def s_gitar():
    iz = np.zeros(1)
    # Em7 (E2 B2 D3 G3 B3 E4) yukarı vuruş: alttan üste 16 ms arayla
    for i, n in enumerate(['E3', 'B3', 'D4', 'G4', 'B4', 'E5']):
        iz = yerlestir(iz, telli(nota(n), 2.0, sonum=0.9975, parlaklik=0.45), i * 0.016, 0.55)
    return yanki(alcak_geciren(iz, 5000), rt60=1.2, karisim=0.2)


# ----------------------------------------------------------------- zil sesleri
def z_marimba():
    tempo = 0.135  # 16'lık
    melodi = ['E5', 'G5', 'A5', 'G5', 'E5', None, 'C5', 'D5',
              'E5', 'G5', 'C6', 'A5', 'G5', None, None, None,
              'E5', 'G5', 'A5', 'G5', 'E5', None, 'D5', 'C5',
              'D5', 'E5', 'G5', 'E5', 'C5', None, None, None]
    bas = ['C4', None, None, None, 'A3', None, None, None,
           'F3', None, None, None, 'G3', None, None, None] * 2
    iz = np.zeros(int(SR * 4.6))
    for i, n in enumerate(melodi):
        if n:
            iz = yerlestir(iz, marimba(nota(n), 0.9), i * tempo, 0.85)
    for i, n in enumerate(bas):
        if n:
            iz = yerlestir(iz, marimba(nota(n), 1.4, parlak=0.5), i * tempo, 0.5)
    iz = yanki(iz, rt60=0.8, karisim=0.14)
    return iz[:int(SR * 4.6)]


def z_klasik():
    """Mekanik telefon zili: çan 20 Hz'de vurulur — 'zırrr zırrr'."""
    def zirr(sure):
        iz = np.zeros(int(SR * (sure + 0.3)))
        vurus = 0.0
        sira = 0
        while vurus < sure:
            f = 1180 if sira % 2 == 0 else 1410
            iz = yerlestir(iz, kismi_ton(f, 0.25, [(1, 1, 0.09), (2.4, 0.5, 0.05), (4.1, 0.25, 0.03)], atak=0.0005), vurus, 0.5)
            vurus += 0.05
            sira += 1
        return iz
    iz = np.zeros(int(SR * 4.2))
    iz = yerlestir(iz, zirr(0.85), 0.0)
    iz = yerlestir(iz, zirr(0.85), 1.25)
    iz = yanki(alcak_geciren(iz, 6500), rt60=0.5, karisim=0.12)
    return iz[:int(SR * 4.2)]


def z_kristal():
    notalar = ['E6', 'B5', 'G#5', 'E5', 'G#5', 'B5', 'E6', 'G#6']
    iz = np.zeros(int(SR * 4.8))
    for i, n in enumerate(notalar):
        iz = yerlestir(iz, kristal(nota(n), 1.3), i * 0.22, 0.6)
    iz = yanki(iz, rt60=1.6, karisim=0.28, parlaklik=7500)
    return iz[:int(SR * 4.8)]


def z_kalimba():
    melodi = [('C6', 0), ('A5', 1), ('G5', 2), ('E5', 3), ('G5', 4.5), ('A5', 5),
              ('C6', 6), ('D6', 7), ('E6', 8), ('D6', 9.5), ('C6', 10),
              ('A5', 11), ('G5', 12)]
    adim = 0.24
    iz = np.zeros(int(SR * 5.2))
    for n, i in melodi:
        iz = yerlestir(iz, kalimba(nota(n), 1.0), i * adim, 0.75)
    for n, i in [('C4', 0), ('A3', 4), ('F3', 8)]:
        iz = yerlestir(iz, kalimba(nota(n), 1.6), i * adim, 0.45)
    iz = yanki(iz, rt60=1.3, karisim=0.22)
    return iz[:int(SR * 5.2)]


def z_retro():
    adim = 0.09
    desen = ['C5', 'E5', 'G5', 'C6', 'G5', 'E5', 'C5', 'E5',
             'A4', 'C5', 'E5', 'A5', 'E5', 'C5', 'A4', 'C5',
             'F4', 'A4', 'C5', 'F5', 'C5', 'A4', 'G4', 'B4',
             'D5', 'G5', 'D5', 'B4', 'G5', None, 'G5', None]
    iz = np.zeros(int(SR * 3.6))
    for i, n in enumerate(desen):
        if not n:
            continue
        x = kare(nota(n), adim * 0.92, darbe=0.25)
        zarf = np.exp(-zaman(adim * 0.92) / 0.09)
        iz = yerlestir(iz, yumusak_bitis(yumusak_baslangic(x * zarf, 0.002), 0.006), i * adim, 0.35)
    iz = alcak_geciren(iz, 4200)
    iz = yanki(iz, rt60=0.6, karisim=0.14)
    return iz[:int(SR * 3.6)]


def z_sakin():
    iz = np.zeros(int(SR * 6.4))
    iz = yerlestir(iz, ped([nota('C4'), nota('E4'), nota('G4'), nota('B4')], 3.2, atak=0.6, birak=1.0), 0.0, 0.7)
    iz = yerlestir(iz, ped([nota('A3'), nota('C4'), nota('E4'), nota('G4')], 3.2, atak=0.6, birak=1.0), 3.0, 0.7)
    for n, an in [('E5', 0.3), ('G5', 0.9), ('B5', 1.5), ('C6', 2.1),
                  ('A5', 3.3), ('G5', 3.9), ('E5', 4.5), ('C5', 5.1)]:
        iz = yerlestir(iz, telli(nota(n), 1.4, sonum=0.997, parlaklik=0.3), an, 0.5)
    iz = yanki(iz, rt60=2.0, karisim=0.3, parlaklik=4500)
    return iz[:int(SR * 6.4)]


def z_neon():
    adim = 0.15
    iz = np.zeros(int(SR * 4.4))
    akor = [('A4', 'C5', 'E5'), ('F4', 'A4', 'C5'), ('C5', 'E5', 'G5'), ('G4', 'B4', 'D5')]
    for blok, (a, b, c) in enumerate(akor):
        for j, n in enumerate([a, b, c, b, c, b, a, b]):
            an = (blok * 8 + j) * adim * 0.5
            t = zaman(0.14)
            f = nota(n)
            faz = 2 * np.pi * f * t
            x = np.sin(faz + 1.6 * np.exp(-t / 0.04) * np.sin(2 * faz)) * np.exp(-t / 0.05)
            iz = yerlestir(iz, birakma(yumusak_baslangic(x, 0.002)), an, 0.55)
    # alt nabız
    for k in range(16):
        t = zaman(0.12)
        x = np.sin(2 * np.pi * 55 * t + 2 * np.exp(-t / 0.02) * np.sin(2 * np.pi * 110 * t)) * np.exp(-t / 0.05)
        iz = yerlestir(iz, birakma(yumusak_baslangic(x, 0.002)), k * adim, 0.45)
    iz = yanki(alcak_geciren(iz, 6500), rt60=1.0, karisim=0.22, parlaklik=7000)
    return iz[:int(SR * 4.4)]


BILDIRIM = {
    'kristal': s_kristal, 'damla': s_damla, 'pit': s_pit,
    'marimba': s_marimba, 'kampana': s_kampana, 'neon': s_neon,
    'kus': s_kus, 'dingdong': s_dingdong, 'arp': s_arp,
    'kalimba': s_kalimba, 'yumusak': s_yumusak, 'tik': s_tik,
    'gitar': s_gitar,
}
ZIL = {
    'zil_marimba': z_marimba, 'zil_klasik': z_klasik,
    'zil_kristal': z_kristal, 'zil_kalimba': z_kalimba,
    'zil_retro': z_retro, 'zil_sakin': z_sakin, 'zil_neon': z_neon,
}


def yaz_wav(yol, x):
    import wave
    x16 = np.clip(x, -1, 1)
    x16 = (x16 * 32767).astype(np.int16)
    with wave.open(yol, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(x16.tobytes())


def main():
    cikti = sys.argv[1]
    os.makedirs(f'{cikti}/wav', exist_ok=True)
    os.makedirs(f'{cikti}/ogg', exist_ok=True)
    for tur, tablo in (('bildirim', BILDIRIM), ('zil', ZIL)):
        for ad, fn in tablo.items():
            # 25 Hz altı (DC, gürültü kayması) her seste atılır: hoparlörde
            # "güm" yapmasın, ses yüksekliği boşa harcanmasın.
            x = yuksek_geciren(fn(), 25)
            if tur == 'bildirim':
                # Bildirim kısa olmalı: -50 dB altı kuyruk atılır, en fazla
                # 2.4 sn; son 0.25 sn yumuşakça söner.
                x = kirp_sessizlik(x, esik=3e-3, kuyruk=0.05)
                x = x[:int(SR * 2.4)]
                x = esit_yukseklik(x, HEDEF_RMS.get(ad, 0.15))
                x = yumusak_bitis(x, 0.25)
            else:
                x = normalize(x, -1.0)
            x = yumusak_bitis(yumusak_baslangic(x, 0.002), 0.04 if tur == 'zil' else 0.06)
            wav = f'{cikti}/wav/{ad}.wav'
            ogg = f'{cikti}/ogg/{ad}.ogg'
            yaz_wav(wav, x)
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', wav, '-c:a', 'libvorbis',
                            '-q:a', '5', '-ar', str(SR), '-ac', '1', ogg], check=True)
            print(f'{tur:9s} {ad:12s} {len(x)/SR:5.2f} sn  {os.path.getsize(ogg)//1024:4d} KB')


if __name__ == '__main__':
    main()
