import ast
import tempfile
from pathlib import Path

import hashlib
import pandas as pd

ROOT = Path(__file__).parents[1]
PROJECT_ROOT = ROOT.parent
SOURCE = ROOT / "python" / "04_full_reproduction.py"
text = SOURCE.read_text(encoding="utf-8")
ast.parse(text)

runner_text = (ROOT / "tools" / "run_yu_full_reproduction_windows.ps1").read_text(encoding="utf-8")
for token in (
    '[ValidateSet("off","on")]',
    '[string]$YYScoreMode = "off"',
    'if ($YYScoreMode -eq "on") { Invoke-RStage "yys" }',
    'Mode=yys requires -YYScoreMode on',
    '"--yys-mode", $YYScoreMode',
    '"--prediction-panel-mode", $PredictionPanelMode',
    '"--panel-mapping-file", $PanelMappingFile',
    '[ValidateSet("published_257","local_reselected","custom")]',
    '"--custom-protein-panel-file", $CustomProteinPanelFile',
    '"--custom-proteins", $CustomProteins',
    '"--figure4_extra_projects=$Figure4ExtraProject"',
    '"--figure4_extra_outcomes=$Figure4ExtraOutcome"',
    '"--figure4_extra_labels=$Figure4ExtraLabel"',
    'lightgbm 3.3.2',
):
    assert token in runner_text, token

required = (
    "derivation_bonferroni_candidate_union.csv",
    "selected_to_30pct",
    "final_cross_endpoint_protein_union.csv",
    "local_reselected_cross_endpoint_protein_union.csv",
    "published_257_cross_endpoint_protein_union.csv",
    "published_257_panel_mapping.csv",
    "prediction_panel_mode",
    "SCORE2",
    "Protein",
    "Protein_SCORE2",
    "Protein_YYScore",
    "Protein_SCORE2_YYScore",
    "paired_design_contract",
    "difference != [\"YYScore\"]",
    "ThreadPoolExecutor",
    "test_predictions_not_used_for_selection_or_tuning",
    "derivation_x = load_proteins(args.raw_protein_file, candidates, derivation)",
    'if yys_mode == "off"',
    '"yys_mode=on requires both yys_score_derivation.csv',
    'parser.add_argument("--yys-mode", choices=["off", "on"], default="off")',
    '"--prediction-panel-mode", choices=["published_257", "local_reselected", "custom"]',
    'parser.add_argument("--custom-protein-panel-file", default="")',
    'parser.add_argument("--custom-proteins", default="")',
    '"endpoint_ids": endpoints',
    '"custom_cross_endpoint_protein_union.csv"',
    '"custom_protein_identifier_mapping.csv"',
    'Formal reproduction requires Python',
    'Formal reproduction requires lightgbm',
    'summary.get("yys_mode_requested") == args.yys_mode',
)
for token in required:
    assert token in text, token

assert "event_" in text
assert "importance_cumulative_fraction" in text
assert 'indicator="__protein_merge"' in text
assert '"missing_value_policy": "LightGBM native missing-value handling"' in text
assert "Protein input has no values" not in text

tree = ast.parse(text)
load_yys_node = next(
    node for node in tree.body
    if isinstance(node, ast.FunctionDef) and node.name == "load_yys_scores"
)
namespace = {
    "Path": Path,
    "pd": None,
    "normalize_eid": None,
}
exec(compile(ast.Module(body=[load_yys_node], type_ignores=[]), str(SOURCE), "exec"), namespace)
load_yys_scores = namespace["load_yys_scores"]
derivation = {"eid": ["1"]}
test = {"eid": ["2"]}
with tempfile.TemporaryDirectory() as temp_dir:
    train_off, test_off, available = load_yys_scores(temp_dir, derivation, test, "off")
    assert not available and train_off is derivation and test_off is test
    try:
        load_yys_scores(temp_dir, derivation, test, "on")
    except RuntimeError as error:
        assert "requires both" in str(error)
    else:
        raise AssertionError("yys_mode=on did not fail when YYScore files were absent")

custom_nodes = [
    node for node in tree.body
    if isinstance(node, ast.FunctionDef) and node.name in {
        "sha_text", "read_table", "file_sha256", "unique_in_order", "resolve_custom_panel"
    }
]
custom_namespace = {"Path": Path, "pd": pd, "hashlib": hashlib}
exec(compile(ast.Module(body=custom_nodes, type_ignores=[]), str(SOURCE), "exec"), custom_namespace)
resolve_custom_panel = custom_namespace["resolve_custom_panel"]
with tempfile.TemporaryDirectory() as temp_dir:
    temp = Path(temp_dir)
    raw = temp / "protein.tsv"
    panel = temp / "panel.csv"
    pd.DataFrame({"eid": ["1"], "gdf15": [1.0], "nppb": [2.0], "adm": [3.0]}).to_csv(
        raw, sep="\t", index=False
    )
    pd.DataFrame({"feature_id": ["GDF15", "NPPB", "GDF15"]}).to_csv(panel, index=False)
    features, manifest = resolve_custom_panel(raw, panel, "ADM,NPPB")
    assert features == ["gdf15", "nppb", "adm"]
    assert manifest["feature_n"] == 3
    assert manifest["file_column"] == "feature_id"
    try:
        resolve_custom_panel(raw, panel, "MISSING_PROTEIN")
    except RuntimeError as error:
        assert "absent from the raw protein table" in str(error)
    else:
        raise AssertionError("Missing custom protein did not fail")

load_protein_nodes = [
    node for node in tree.body
    if isinstance(node, ast.FunctionDef) and node.name in {"read_table", "normalize_eid", "load_proteins"}
]
protein_namespace = {"pd": pd}
exec(compile(ast.Module(body=load_protein_nodes, type_ignores=[]), str(SOURCE), "exec"), protein_namespace)
load_proteins = protein_namespace["load_proteins"]
with tempfile.TemporaryDirectory() as temp_dir:
    raw = Path(temp_dir) / "protein.tsv"
    pd.DataFrame({
        "eid": ["1", "2"],
        "p1": [1.0, float("nan")],
        "p2": [2.0, float("nan")],
    }).to_csv(raw, sep="\t", index=False)
    loaded = load_proteins(raw, ["p1", "p2"], pd.DataFrame({"eid": ["1", "2"]}))
    assert len(loaded) == 2
    assert loaded.attrs["protein_coverage"]["all_feature_missing_n"] == 1
    try:
        load_proteins(raw, ["p1", "p2"], pd.DataFrame({"eid": ["3"]}))
    except RuntimeError as error:
        assert "has no row" in str(error)
    else:
        raise AssertionError("Absent protein EID did not fail")

step_runner_text = (ROOT / "tools" / "run_yu_steps_windows.ps1").read_text(encoding="utf-8")
for token in (
    '"D:/"',
    'Join-Path $Dir0 "data/ukb/phe"',
    'Join-Path $Dir0 "analysis"',
    'YuProteinAnalysis/paths.json',
    'Remember-Path $ProfileKey $selected',
    '$FullRunner = Join-Path $ProjectDir "f/tools/run_yu_full_reproduction_windows.ps1"',
    '[ValidateSet("Auto", "Dialog", "Console", "Off")]',
    '[string]$PathPromptMode = "Auto"',
    'New-Object System.Windows.Forms.OpenFileDialog',
    'New-Object System.Windows.Forms.FolderBrowserDialog',
    'Read-Host "Enter an existing $PathType path for $Label (Q to cancel)"',
    'Resolve-SelectedInputPaths $SelectedSteps',
    '[string]$GenotypeMode = "DirectNas"',
    '[Alias("EndpointSubset")]',
    '[string]$Disease = "all"',
    '[ValidateSet("local_reselected", "published_257", "custom")]',
    '[string]$ProteinPanel = "local_reselected"',
    'EndpointSubset = $Disease',
    'CustomProteinPanelFile = $ModelProteinFile',
    'CustomProteins = $ModelProteins',
    'Figure4ExtraProject = $Figure4ExtraProject',
    'Figure4ExtraOutcome = $Figure4ExtraOutcome',
    'Figure4ExtraLabel = $Figure4ExtraLabel',
    'The frozen yu_proteomic_repo_v3 project is protected',
):
    assert token in step_runner_text, token

short_runner_text = (PROJECT_ROOT / "yu.ps1").read_text(encoding="utf-8")
assert 'f/tools/run_yu_steps_windows.ps1' in short_runner_text
assert '& $runner @args' in short_runner_text

print("ALL FULL-REPRODUCTION PYTHON STATIC TESTS PASSED")
