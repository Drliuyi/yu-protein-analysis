import importlib.util
from pathlib import Path

import numpy as np


MODULE = Path(__file__).parents[1] / "python" / "09_yys_v2_lightgbm.py"
spec = importlib.util.spec_from_file_location("yys_v2_lightgbm", MODULE)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def test_gain_selection_includes_crossing_feature():
    table = mod.select_to_cumulative_gain(["A", "B", "C", "D"], [45, 30, 20, 5], 0.50)
    assert table.loc[table.selected_to_30pct, "protein"].tolist() == ["A", "B"]


def test_protein_yin_and_yy_scores_have_matched_dimensions():
    clinical = np.arange(12, dtype=np.float32).reshape(4, 3)
    proteins = np.arange(20, dtype=np.float32).reshape(4, 5)
    yin = np.linspace(-1, 1, 4, dtype=np.float32)
    yy = np.linspace(1, -1, 4, dtype=np.float32)
    yin_x = mod.model_matrix("CAD_YinPanel_YinScore", clinical, proteins, yin, yy)
    yy_x = mod.model_matrix("CAD_YinPanel_YYScore", clinical, proteins, yin, yy)
    assert yin_x.shape == yy_x.shape == (4, 6)
    np.testing.assert_array_equal(yin_x[:, :-1], yy_x[:, :-1])
    np.testing.assert_array_equal(yin_x[:, -1], yin)
    np.testing.assert_array_equal(yy_x[:, -1], yy)


def test_combined_yin_and_yy_scores_have_matched_dimensions():
    clinical = np.arange(12, dtype=np.float32).reshape(4, 3)
    proteins = np.arange(20, dtype=np.float32).reshape(4, 5)
    yin = np.linspace(-1, 1, 4, dtype=np.float32)
    yy = np.linspace(1, -1, 4, dtype=np.float32)
    yin_x = mod.model_matrix("BasicClinical_CAD_YinPanel_YinScore", clinical, proteins, yin, yy)
    yy_x = mod.model_matrix("BasicClinical_CAD_YinPanel_YYScore", clinical, proteins, yin, yy)
    assert yin_x.shape == yy_x.shape == (4, 9)
    np.testing.assert_array_equal(yin_x[:, :-1], yy_x[:, :-1])


if __name__ == "__main__":
    test_gain_selection_includes_crossing_feature()
    test_protein_yin_and_yy_scores_have_matched_dimensions()
    test_combined_yin_and_yy_scores_have_matched_dimensions()
    print("ALL TESTS PASSED")
