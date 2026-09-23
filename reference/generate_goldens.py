"""Independent SciPy reference for neuroTune spectral features.

Writes golden vectors consumed by the Dart tests. The Dart implementation does
not call this script; the numbers are the comparison target.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from scipy import signal


def sine(hz: float, fs: float, seconds: float, amplitude: float = 20.0) -> np.ndarray:
    t = np.arange(int(round(seconds * fs))) / fs
    return amplitude * np.sin(2 * np.pi * hz * t)


def filter_signal(samples: np.ndarray, fs: float, notch_hz: float = 50.0) -> np.ndarray:
    sos = signal.butter(4, [1, 40], btype="bandpass", fs=fs, output="sos")
    notch_b, notch_a = signal.iirnotch(notch_hz, 30, fs=fs)
    notch_sos = signal.tf2sos(notch_b, notch_a)
    filtered = signal.sosfilt(notch_sos, samples)
    return signal.sosfilt(sos, filtered)


def band_power(samples: np.ndarray, fs: float, low: float, high: float) -> float:
    freqs, psd = signal.welch(
        samples[-1024:],
        fs=fs,
        nperseg=512,
        noverlap=256,
        detrend="constant",
        scaling="density",
    )
    df = freqs[1] - freqs[0]
    mask = (freqs >= low) & (freqs < high)
    return float(np.sum(psd[mask]) * df)


def case(hz: float, fs: float = 256.0) -> dict:
    raw = sine(hz, fs, 8)
    filtered = filter_signal(raw, fs)
    theta = band_power(filtered, fs, 4, 8)
    alpha = band_power(filtered, fs, 8, 13)
    beta = band_power(filtered, fs, 13, 30)
    total = band_power(filtered, fs, 1, 40)
    freqs, psd = signal.welch(
        filtered[-1024:],
        fs=fs,
        nperseg=512,
        noverlap=256,
        detrend="constant",
        scaling="density",
    )
    return {
        "hz": hz,
        "filtered": filtered.tolist(),
        "theta": theta,
        "alpha": alpha,
        "beta": beta,
        "total": total,
        "relative_theta": theta / total,
        "relative_alpha": alpha / total,
        "relative_beta": beta / total,
        "peak_hz": float(freqs[int(np.argmax(psd))]),
    }


def normalization() -> dict:
    baseline = [0.20, 0.22, 0.18, 0.25, 0.19]
    observed = [0.40, 0.42, 0.38]
    mean = float(np.mean(baseline))
    std = float(np.sqrt(np.mean((np.array(baseline) - mean) ** 2)))
    scores = [(value - mean) / std for value in observed]
    reward = float(np.clip(np.mean(scores), -3, 3))
    return {
        "baseline": baseline,
        "observed": observed,
        "mean": mean,
        "std": std,
        "reward": reward,
    }


def main() -> None:
    fs = 256.0
    probe = np.array([1, 2, 3, 4, 5, 6, 7, 8], dtype=float)
    spectrum = np.fft.rfft(probe)
    payload = {
        "fs": fs,
        "fft_input": probe.tolist(),
        "fft_real": spectrum.real.tolist(),
        "fft_imag": spectrum.imag.tolist(),
        "cases": [case(6), case(10), case(20)],
        "normalization": normalization(),
    }
    destination = Path(__file__).resolve().parents[1] / "packages" / "neurotune_core" / "test" / "goldens" / "spectral.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(payload))
    print(destination)


if __name__ == "__main__":
    main()
