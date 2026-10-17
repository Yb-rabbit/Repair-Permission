#!/usr/bin/env python3
"""Generate the minimal diegetic soundscape for Repair Permission.

Only the Python standard library is used. Run from the project root:

    python tools/generate_audio.py

The output is 44.1 kHz / 16-bit / stereo WAV in res://audio/.
All loops are crossfaded at the seam so they can be looped in Godot.
"""

import math
import os
import random
import struct
import wave

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio")
random.seed(77077)


def clamp(value, low=-1.0, high=1.0):
    return low if value < low else high if value > high else value


def white(count):
    return [random.uniform(-1.0, 1.0) for _ in range(count)]


def lowpass(samples, alpha):
    out = []
    last = 0.0
    for value in samples:
        last += alpha * (value - last)
        out.append(last)
    return out


def highpass(samples, alpha):
    out = []
    last_in = 0.0
    last_out = 0.0
    for value in samples:
        last_out = alpha * (last_out + value - last_in)
        last_in = value
        out.append(last_out)
    return out


def brown(samples, leak=0.997, drive=0.03):
    out = []
    value = 0.0
    for sample in samples:
        value = leak * value + drive * sample
        out.append(value)
    return out


def write_stereo(name, left, right, peak_db=-3.0):
    peak = max(max(abs(v) for v in left), max(abs(v) for v in right), 1e-9)
    gain = (10.0 ** (peak_db / 20.0)) / peak
    frames = bytearray()
    for l_value, r_value in zip(left, right):
        frames += struct.pack("<hh", int(clamp(l_value * gain) * 32767),
                              int(clamp(r_value * gain) * 32767))
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(bytes(frames))
    print("wrote", path)


def seamless(left, right, seconds=0.75):
    """Crossfade the tail into the head so the full file loops without a click."""
    fade = int(seconds * SR)
    length = len(left) - fade
    out_l = left[:length]
    out_r = right[:length]
    for i in range(fade):
        mix = i / fade
        out_l[i] = left[i] * mix + left[length + i] * (1.0 - mix)
        out_r[i] = right[i] * mix + right[length + i] * (1.0 - mix)
    return out_l, out_r


def add_click(left, right, at, amp=0.18):
    start = int(at * SR)
    duration = int(0.035 * SR)
    for j in range(duration):
        t = j / SR
        env = math.exp(-t / 0.004)
        value = amp * env * (random.uniform(-1.0, 1.0) * 0.65
                              + math.sin(2.0 * math.pi * 1700.0 * t) * 0.7)
        if start + j < len(left):
            left[start + j] += value
            right[start + j] += value * 0.92


def add_paper(left, right, at, seconds=0.16, amp=0.10):
    start = int(at * SR)
    duration = int(seconds * SR)
    grain = lowpass(white(duration), 0.55)
    for j in range(duration):
        t = j / SR
        env = math.sin(math.pi * min(1.0, t / seconds)) ** 1.4
        value = amp * env * grain[j]
        if start + j < len(left):
            left[start + j] += value
            right[start + j] += value * 0.85


def make_room_tone():
    seconds = 30.0
    fade = 0.9
    count = int((seconds + fade) * SR)
    fan_l = lowpass(white(count), 0.055)
    fan_r = lowpass(white(count), 0.050)
    rumble_l = brown(white(count))
    rumble_r = brown(white(count))
    left = []
    right = []
    for i in range(count):
        t = i / SR
        airflow = 0.55 + 0.08 * math.sin(2.0 * math.pi * 0.1 * t) \
            + 0.04 * math.sin(2.0 * math.pi * 0.2 * t + 1.1)
        hum = (0.060 * math.sin(2.0 * math.pi * 50.0 * t)
               + 0.028 * math.sin(2.0 * math.pi * 100.0 * t + 0.7)
               + 0.012 * math.sin(2.0 * math.pi * 150.0 * t + 1.4))
        ballast = 0.007 * math.sin(2.0 * math.pi * 120.0 * t + 0.3)
        left.append(fan_l[i] * 0.40 * airflow + rumble_l[i] * 0.17 + hum + ballast)
        right.append(fan_r[i] * 0.40 * airflow + rumble_r[i] * 0.17
                     + hum * 0.96 + ballast * 0.9)
    left, right = seamless(left, right, fade)
    write_stereo("room_tone.wav", left, right, -8.0)


def make_old_idle():
    seconds = 12.0
    fade = 0.55
    count = int((seconds + fade) * SR)
    fan = lowpass(white(count), 0.085)
    paper = lowpass(white(count), 0.45)
    left = []
    right = []
    for i in range(count):
        t = i / SR
        hum = (0.16 * math.sin(2.0 * math.pi * 50.0 * t)
               + 0.055 * math.sin(2.0 * math.pi * 100.0 * t + 0.2)
               + 0.020 * math.sin(2.0 * math.pi * 150.0 * t + 1.0))
        bed = fan[i] * 0.16 + paper[i] * 0.018
        left.append(hum + bed)
        right.append(hum * 0.94 + bed * 0.9)
    add_click(left, right, 2.2, 0.16)
    add_click(left, right, 5.7, 0.11)
    add_click(left, right, 9.1, 0.14)
    add_paper(left, right, 7.4, 0.18, 0.075)
    left, right = seamless(left, right, fade)
    write_stereo("old_idle.wav", left, right, -11.0)


def make_new_idle():
    seconds = 16.0
    fade = 0.6
    count = int((seconds + fade) * SR)
    air = highpass(lowpass(white(count), 0.32), 0.012)
    left = []
    right = []
    for i in range(count):
        t = i / SR
        hum = (0.028 * math.sin(2.0 * math.pi * 120.0 * t)
               + 0.012 * math.sin(2.0 * math.pi * 240.0 * t + 0.5))
        shimmer = 0.0045 * math.sin(2.0 * math.pi * 2100.0 * t) \
            * (0.55 + 0.45 * math.sin(2.0 * math.pi * 0.125 * t))
        left.append(air[i] * 0.035 + hum + shimmer)
        right.append(air[i] * -0.031 + hum * 0.95 + shimmer * 0.9)
    left, right = seamless(left, right, fade)
    write_stereo("new_idle.wav", left, right, -14.0)


def make_tension_hum():
    seconds = 24.0
    fade = 0.8
    count = int((seconds + fade) * SR)
    rumble = brown(white(count))
    left = []
    right = []
    for i in range(count):
        t = i / SR
        beat = 0.75 + 0.25 * math.sin(2.0 * math.pi * 0.25 * t)
        hum = (0.20 * math.sin(2.0 * math.pi * 47.5 * t)
               + 0.075 * math.sin(2.0 * math.pi * 95.0 * t + 0.8)
               + 0.030 * math.sin(2.0 * math.pi * 142.5 * t + 1.7))
        left.append(hum * beat + rumble[i] * 0.10)
        right.append(hum * beat * 0.93 + rumble[i] * 0.105)
    left, right = seamless(left, right, fade)
    write_stereo("tension_hum.wav", left, right, -9.0)


def make_print():
    seconds = 0.30
    count = int(seconds * SR)
    hiss = lowpass(white(count), 0.45)
    left = []
    right = []
    for i in range(count):
        t = i / SR
        env = math.exp(-t / 0.12)
        pulse = max(0.0, math.sin(2.0 * math.pi * 95.0 * t)) ** 0.55
        needle = math.sin(2.0 * math.pi * 1850.0 * t) * 0.45
        value = (pulse * 0.62 + needle * pulse + hiss[i] * 0.12) * env
        left.append(value)
        right.append(value * 0.93)
    write_stereo("old_print.wav", left, right, -2.5)


def make_relay():
    seconds = 0.12
    count = int(seconds * SR)
    left = [0.0] * count
    right = [0.0] * count
    for at, amp in ((0.0, 0.9), (0.038, 0.55)):
        start = int(at * SR)
        for j in range(int(0.030 * SR)):
            if start + j >= count:
                break
            t = j / SR
            env = math.exp(-t / 0.0045)
            value = amp * env * (random.uniform(-1.0, 1.0) * 0.55
                                  + math.sin(2.0 * math.pi * 1450.0 * t) * 0.8
                                  + math.sin(2.0 * math.pi * 720.0 * t) * 0.35)
            left[start + j] += value
            right[start + j] += value * 0.9
    write_stereo("old_relay.wav", left, right, -2.5)


def make_tick():
    seconds = 0.08
    count = int(seconds * SR)
    left = []
    right = []
    for i in range(count):
        t = i / SR
        attack = min(1.0, t / 0.002)
        env = attack * math.exp(-t / 0.016)
        value = env * (0.55 * math.sin(2.0 * math.pi * 1560.0 * t)
                       + 0.22 * math.sin(2.0 * math.pi * 2340.0 * t))
        left.append(value)
        right.append(value * 0.88)
    write_stereo("new_tick.wav", left, right, -6.0)


def make_chime():
    seconds = 0.85
    count = int(seconds * SR)
    left = [0.0] * count
    right = [0.0] * count
    notes = ((0.0, 1046.5, 0.55), (0.11, 1568.0, 0.42))
    for at, freq, amp in notes:
        start = int(at * SR)
        for j in range(int(0.70 * SR)):
            if start + j >= count:
                break
            t = j / SR
            attack = min(1.0, t / 0.006)
            env = attack * math.exp(-t / 0.26)
            tone = (math.sin(2.0 * math.pi * freq * t)
                    + 0.28 * math.sin(2.0 * math.pi * freq * 2.0 * t)
                    + 0.10 * math.sin(2.0 * math.pi * freq * 3.0 * t))
            right_tone = (math.sin(2.0 * math.pi * (freq + 0.4) * t)
                          + 0.28 * math.sin(2.0 * math.pi * (freq + 0.4) * 2.0 * t)
                          + 0.10 * math.sin(2.0 * math.pi * (freq + 0.4) * 3.0 * t))
            left[start + j] += amp * env * tone
            right[start + j] += amp * env * right_tone
    write_stereo("new_chime.wav", left, right, -4.0)


def main():
    make_room_tone()
    make_old_idle()
    make_new_idle()
    make_tension_hum()
    make_print()
    make_relay()
    make_tick()
    make_chime()


if __name__ == "__main__":
    main()
