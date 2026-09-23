import json
from pathlib import Path

from generate_goldens import band_power, case, filter_signal, normalization, sine


GOLDEN = Path(__file__).resolve().parents[1] / "packages" / "neurotune_core" / "test" / "goldens" / "spectral.json"


def test_golden_file_matches_scipy():
    saved = json.loads(GOLDEN.read_text())
    fresh = case(6)
    assert abs(fresh["peak_hz"] - saved["cases"][0]["peak_hz"]) < 1e-9
    assert abs(fresh["relative_theta"] - saved["cases"][0]["relative_theta"]) < 1e-9


def test_known_sines_land_in_their_bands():
    six = case(6)
    ten = case(10)
    twenty = case(20)
    assert six["peak_hz"] == 6
    assert six["relative_theta"] > 0.9
    assert ten["relative_alpha"] > 0.8
    assert twenty["relative_beta"] > 0.8


def test_band_edges_do_not_double_count_8hz():
    filtered = filter_signal(sine(8, 256, 8), 256)
    theta = band_power(filtered, 256, 4, 8)
    alpha = band_power(filtered, 256, 8, 13)
    assert alpha > theta


def test_normalization_is_clipped_zscore():
    stats = normalization()
    assert stats["std"] > 0
    assert -3 <= stats["reward"] <= 3
    assert stats["reward"] > 1
