#!/usr/bin/env python
"""Local CAD Yu-style LightGBM with matched YinScore and ABCD-YYS v2 extensions."""

import argparse
import hashlib
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import pandas as pd
from lightgbm import LGBMClassifier
from sklearn.metrics import average_precision_score, brier_score_loss, roc_auc_score


MODEL_ORDER = [
    "BasicClinical",
    "CAD_YinPanel",
    "CAD_YinPanel_YinScore",
    "CAD_YinPanel_YYScore",
    "BasicClinical_CAD_YinPanel",
    "BasicClinical_CAD_YinPanel_YinScore",
    "BasicClinical_CAD_YinPanel_YYScore",
]
CLINICAL_NUMERIC = [
    "age", "sex", "sbp", "bp_treatment", "diabetes", "total_cholesterol", "hdl",
]


def sha_lines(values):
    return hashlib.sha256("\n".join(map(str, values)).encode("utf-8")).hexdigest()


def build_model(workers, seed):
    return LGBMClassifier(
        objective="binary", n_estimators=500, max_depth=15, num_leaves=10,
        subsample=0.70, subsample_freq=1, learning_rate=0.01,
        colsample_bytree=0.70, random_state=int(seed), n_jobs=int(workers), verbosity=-1,
    )


def prepare_clinical(participants, train_indices, test_indices):
    train_parts, test_parts, names = [], [], []
    for name in CLINICAL_NUMERIC:
        train = pd.to_numeric(participants.iloc[train_indices][name], errors="coerce").to_numpy(dtype=float)
        test = pd.to_numeric(participants.iloc[test_indices][name], errors="coerce").to_numpy(dtype=float)
        median = float(np.nanmedian(train))
        if not np.isfinite(median):
            raise RuntimeError(f"Clinical variable {name} has no finite derivation values")
        train_parts.append(np.where(np.isfinite(train), train, median).reshape(-1, 1))
        test_parts.append(np.where(np.isfinite(test), test, median).reshape(-1, 1))
        names.append(name)
    smoking_train = participants.iloc[train_indices].smoking.astype("string")
    smoking_test = participants.iloc[test_indices].smoking.astype("string")
    observed = smoking_train.dropna().astype(str)
    if observed.empty:
        raise RuntimeError("Smoking has no observed derivation values")
    mode = observed.mode().iloc[0]
    smoking_train = smoking_train.fillna(mode).astype(str)
    smoking_test = smoking_test.fillna(mode).astype(str)
    categories = sorted(smoking_train.unique().tolist())
    for category in categories[1:]:
        train_parts.append((smoking_train.to_numpy() == category).astype(float).reshape(-1, 1))
        test_parts.append((smoking_test.to_numpy() == category).astype(float).reshape(-1, 1))
        names.append(f"smoking__{category}")
    train = np.column_stack(train_parts).astype(np.float32, copy=False)
    test = np.column_stack(test_parts).astype(np.float32, copy=False)
    if not np.isfinite(train).all() or not np.isfinite(test).all():
        raise RuntimeError("Non-finite Basic clinical values remain after derivation-only imputation")
    return train, test, names


def select_to_cumulative_gain(candidate_names, gain, fraction=0.30):
    table = pd.DataFrame({"protein": list(candidate_names), "gain": np.asarray(gain, dtype=float)})
    total = float(table.gain.sum())
    if not np.isfinite(total) or total <= 0:
        raise RuntimeError("Preliminary CAD LightGBM produced zero total information gain")
    table["normalized_gain"] = table.gain / total
    table = table.sort_values(["normalized_gain", "protein"], ascending=[False, True]).reset_index(drop=True)
    table["gain_rank"] = np.arange(1, len(table) + 1)
    table["cumulative_gain"] = table.normalized_gain.cumsum()
    crossing = int(np.searchsorted(table.cumulative_gain.to_numpy(), fraction, side="left"))
    table["selected_to_30pct"] = table.index <= crossing
    return table


def compute_scores(X, weights, selected_indices, derivation_indices):
    selected = weights.iloc[selected_indices]
    mu = selected.protein_mean_yin.to_numpy(dtype=np.float64)
    sd = selected.protein_sd_yin.to_numpy(dtype=np.float64)
    beta = selected.beta_yin.to_numpy(dtype=np.float64)
    yys = selected.YYS_v2.to_numpy(dtype=np.float64)
    if np.any(~np.isfinite(sd)) or np.any(sd <= 0):
        raise RuntimeError("Selected panel contains an invalid derivation protein SD")
    x_selected = np.asarray(X[:, selected_indices], dtype=np.float32)
    yin_coef = beta / sd
    yy_coef = beta * yys / sd
    yin_raw = np.asarray(x_selected @ yin_coef - np.sum(mu * yin_coef), dtype=float)
    yy_raw = np.asarray(x_selected @ yy_coef - np.sum(mu * yy_coef), dtype=float)
    output, params = {}, {}
    for name, raw in (("YinScore", yin_raw), ("YYScore", yy_raw)):
        center = float(raw[derivation_indices].mean())
        scale = float(raw[derivation_indices].std(ddof=1))
        if not np.isfinite(scale) or scale <= 0:
            raise RuntimeError(f"{name} derivation SD is invalid")
        output[name] = ((raw - center) / scale).astype(np.float32)
        params[name] = {"derivation_mean": center, "derivation_sd": scale}
    return output, params


def model_matrix(name, clinical, proteins, yin_score, yy_score):
    if name == "BasicClinical":
        return clinical
    blocks = []
    if name.startswith("BasicClinical_"):
        blocks.append(clinical)
    blocks.append(proteins)
    if name.endswith("_YinScore"):
        blocks.append(yin_score.reshape(-1, 1))
    elif name.endswith("_YYScore"):
        blocks.append(yy_score.reshape(-1, 1))
    return np.column_stack(blocks).astype(np.float32, copy=False)


def feature_names(name, clinical_names, selected_names):
    if name == "BasicClinical":
        return list(clinical_names)
    names = []
    if name.startswith("BasicClinical_"):
        names.extend(clinical_names)
    names.extend(selected_names)
    if name.endswith("_YinScore"):
        names.append("YinScore")
    elif name.endswith("_YYScore"):
        names.append("YYScore")
    return names


def seed_group(name):
    if name == "BasicClinical":
        return 0
    return 1 if not name.startswith("BasicClinical_") else 2


def metric_row(model_id, y, prediction):
    return {
        "model_id": model_id, "n": int(len(y)), "events": int(np.sum(y)),
        "AUC": float(roc_auc_score(y, prediction)),
        "PR_AUC": float(average_precision_score(y, prediction)),
        "Brier": float(brier_score_loss(y, prediction)),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--analysis-dir", required=True)
    parser.add_argument("--input-dir", required=True)
    parser.add_argument("--workers", type=int, default=16)
    parser.add_argument("--model-jobs", type=int, default=3)
    parser.add_argument("--seed", type=int, default=20260721)
    args = parser.parse_args()

    analysis = Path(args.analysis_dir)
    input_dir = Path(args.input_dir)
    cache = analysis / "01_cache"
    out = analysis / "02_lightgbm"
    out.mkdir(parents=True, exist_ok=True)

    participants = pd.read_csv(cache / "participants.csv.gz", dtype={"eid": str})
    order = pd.read_csv(cache / "protein_order.csv")
    proteins = order.protein.astype(str).tolist()
    weights = pd.read_csv(input_dir / "cad_derivation_ABCD_YYS_v2.csv.gz")
    if len(participants) != 37127 or int(participants.event.sum()) != 3442 or len(proteins) != 2910:
        raise RuntimeError("Local CAD cohort/panel contract failed")
    if weights.protein.astype(str).tolist() != proteins:
        raise RuntimeError("ABCD-YYS v2 protein order does not match the matrix")
    derivation_indices = np.flatnonzero(participants.split.to_numpy() == "derivation")
    holdout_indices = np.flatnonzero(participants.split.to_numpy() == "holdout")
    if len(derivation_indices) + len(holdout_indices) != len(participants):
        raise RuntimeError("Split contains an unrecognized label")
    X = np.memmap(
        cache / "protein_matrix_37127x2910_float32.bin", dtype="<f4", mode="r",
        shape=(37127, 2910), order="C",
    )
    if not np.isfinite(X).all():
        raise RuntimeError("Protein matrix contains non-finite values")
    y = participants.event.to_numpy(dtype=int)
    y_derivation = y[derivation_indices]
    y_holdout = y[holdout_indices]

    candidate_mask = weights.derivation_bonferroni_candidate.astype(bool).to_numpy()
    candidate_indices = np.flatnonzero(candidate_mask)
    if not len(candidate_indices):
        raise RuntimeError("No derivation Bonferroni CAD candidates")
    candidate_x = np.asarray(X[np.ix_(derivation_indices, candidate_indices)], dtype=np.float32)
    preliminary = build_model(args.workers, args.seed)
    preliminary.fit(candidate_x, y_derivation)
    selection = select_to_cumulative_gain(
        [proteins[i] for i in candidate_indices],
        preliminary.booster_.feature_importance(importance_type="gain"), 0.30,
    )
    selection["p_yin"] = selection.protein.map(weights.set_index("protein").p_yin)
    selection["p_bonferroni"] = selection.protein.map(weights.set_index("protein").p_bonferroni)
    selection.to_csv(out / "cad_candidate_gain_selection.csv", index=False)
    selected_names = selection.loc[selection.selected_to_30pct, "protein"].tolist()
    index_by_name = {name: i for i, name in enumerate(proteins)}
    selected_indices = np.array([index_by_name[name] for name in selected_names], dtype=int)
    selected_hash = sha_lines(selected_names)
    del candidate_x, preliminary

    scores, score_params = compute_scores(X, weights, selected_indices, derivation_indices)
    selected_derivation = np.asarray(X[np.ix_(derivation_indices, selected_indices)], dtype=np.float32)
    selected_holdout = np.asarray(X[np.ix_(holdout_indices, selected_indices)], dtype=np.float32)
    clinical_derivation, clinical_holdout, clinical_names = prepare_clinical(
        participants, derivation_indices, holdout_indices
    )

    # Ten-fold derivation diagnostics follow the Yu-style workflow. Selection and
    # ABCD-YYS are frozen from the complete derivation set; the hold-out is untouched.
    inner_fold = participants.iloc[derivation_indices].inner_fold.to_numpy(dtype=int)
    if set(np.unique(inner_fold)) != set(range(1, 11)):
        raise RuntimeError("Expected ten derivation inner folds")
    oof = {name: np.full(len(derivation_indices), np.nan, dtype=float) for name in MODEL_ORDER}
    fold_rows = []
    workers_per_model = max(1, int(args.workers) // max(1, int(args.model_jobs)))
    for fold in range(1, 11):
        inner_train = np.flatnonzero(inner_fold != fold)
        inner_valid = np.flatnonzero(inner_fold == fold)
        clinical_train, clinical_valid, clinical_inner_names = prepare_clinical(
            participants, derivation_indices[inner_train], derivation_indices[inner_valid]
        )

        def fit_inner(name):
            train_x = model_matrix(
                name, clinical_train, selected_derivation[inner_train],
                scores["YinScore"][derivation_indices][inner_train],
                scores["YYScore"][derivation_indices][inner_train],
            )
            valid_x = model_matrix(
                name, clinical_valid, selected_derivation[inner_valid],
                scores["YinScore"][derivation_indices][inner_valid],
                scores["YYScore"][derivation_indices][inner_valid],
            )
            model = build_model(workers_per_model, args.seed + fold * 10 + seed_group(name))
            model.fit(train_x, y_derivation[inner_train])
            return name, model.predict_proba(valid_x)[:, 1]

        with ThreadPoolExecutor(max_workers=max(1, int(args.model_jobs))) as executor:
            fitted = list(executor.map(fit_inner, MODEL_ORDER))
        for name, prediction in fitted:
            oof[name][inner_valid] = prediction
            fold_rows.append({"inner_fold": fold, **metric_row(name, y_derivation[inner_valid], prediction)})

    if any(np.isnan(value).any() for value in oof.values()):
        raise RuntimeError("Derivation ten-fold predictions are incomplete")

    holdout_predictions = []
    importance = []
    design = []

    def fit_final(name):
        train_x = model_matrix(
            name, clinical_derivation, selected_derivation,
            scores["YinScore"][derivation_indices], scores["YYScore"][derivation_indices],
        )
        test_x = model_matrix(
            name, clinical_holdout, selected_holdout,
            scores["YinScore"][holdout_indices], scores["YYScore"][holdout_indices],
        )
        model = build_model(workers_per_model, args.seed + 1000 + seed_group(name))
        model.fit(train_x, y_derivation)
        pred = model.predict_proba(test_x)[:, 1]
        names = feature_names(name, clinical_names, selected_names)
        gain = model.booster_.feature_importance(importance_type="gain").astype(float)
        if len(names) != len(gain):
            raise RuntimeError(f"Feature-name contract failed for {name}")
        return name, pred, names, gain, train_x.shape[1]

    with ThreadPoolExecutor(max_workers=max(1, int(args.model_jobs))) as executor:
        final_models = list(executor.map(fit_final, MODEL_ORDER))
    for name, prediction, names, gain, feature_n in final_models:
        holdout_predictions.append(pd.DataFrame({
            "eid": participants.iloc[holdout_indices].eid.to_numpy(),
            "time": participants.iloc[holdout_indices].time.to_numpy(),
            "event": y_holdout,
            "model_id": name,
            "prediction": prediction,
        }))
        importance.append(pd.DataFrame({"model_id": name, "feature": names, "gain": gain}))
        design.append({
            "model_id": name, "feature_n": feature_n,
            "selected_protein_n": 0 if name == "BasicClinical" else len(selected_names),
            "selected_protein_hash": "" if name == "BasicClinical" else selected_hash,
            "contains_basic_clinical": name == "BasicClinical" or name.startswith("BasicClinical_"),
            "score_feature": "YinScore" if name.endswith("_YinScore") else (
                "YYScore" if name.endswith("_YYScore") else "none"
            ),
        })

    holdout = pd.concat(holdout_predictions, ignore_index=True)
    holdout.to_csv(out / "holdout_predictions.csv.gz", index=False)
    pd.DataFrame([metric_row(name, y_holdout, frame.prediction.to_numpy())
                  for name, frame in holdout.groupby("model_id", sort=False)]).to_csv(
        out / "holdout_metrics.csv", index=False
    )
    pd.DataFrame(fold_rows).to_csv(out / "derivation_inner_fold_metrics.csv", index=False)
    pd.DataFrame([metric_row(name, y_derivation, value) for name, value in oof.items()]).to_csv(
        out / "derivation_oof_metrics.csv", index=False
    )
    pd.concat(importance, ignore_index=True).to_csv(out / "holdout_model_feature_importance.csv.gz", index=False)
    pd.DataFrame(design).to_csv(out / "model_design_contract.csv", index=False)
    pd.DataFrame({
        "eid": participants.eid,
        "split": participants.split,
        "YinScore": scores["YinScore"],
        "YYScore": scores["YYScore"],
    }).to_csv(out / "participant_scores.csv.gz", index=False)
    with open(out / "score_parameters.json", "w", encoding="utf-8") as handle:
        json.dump(score_params, handle, indent=2)

    contract = pd.DataFrame(design).set_index("model_id")
    pairs = [
        ("CAD_YinPanel_YinScore", "CAD_YinPanel_YYScore"),
        ("BasicClinical_CAD_YinPanel_YinScore", "BasicClinical_CAD_YinPanel_YYScore"),
    ]
    for yin_name, yy_name in pairs:
        yin = contract.loc[yin_name]
        yy = contract.loc[yy_name]
        if yin.selected_protein_hash != yy.selected_protein_hash or int(yin.feature_n) != int(yy.feature_n):
            raise RuntimeError(f"Matched YinScore/YYScore design failed: {yin_name} vs {yy_name}")

    manifest = {
        "status": "PASS",
        "analysis": "our CAD outcome with Yu-style derivation selection and ABCD-YYS v2",
        "split": "two-thirds derivation and one-third locked hold-out",
        "derivation_n": int(len(derivation_indices)),
        "derivation_events": int(y_derivation.sum()),
        "holdout_n": int(len(holdout_indices)),
        "holdout_events": int(y_holdout.sum()),
        "protein_n_before_selection": len(proteins),
        "bonferroni_candidate_n": int(len(candidate_indices)),
        "selected_protein_n": int(len(selected_indices)),
        "selected_protein_hash": selected_hash,
        "selection": "derivation-only adjusted Cox p < 0.05/2910 then preliminary LightGBM cumulative gain through 30 percent",
        "inner_folds": 10,
        "score_comparison": "same selected proteins and same feature count; YinScore versus YYScore",
        "not_used": ["published Yu protein panel", "fixed Yu outcomes", "fixed Yu split", "permutation control"],
        "parameters": {
            "n_estimators": 500, "max_depth": 15, "num_leaves": 10,
            "subsample": 0.70, "subsample_freq": 1,
            "learning_rate": 0.01, "colsample_bytree": 0.70,
        },
        "workers": args.workers, "model_jobs": args.model_jobs, "seed": args.seed,
        "lightgbm_version": __import__("lightgbm").__version__,
        "sklearn_version": __import__("sklearn").__version__,
    }
    with open(out / "training_manifest.json", "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)
    print(json.dumps(manifest))


if __name__ == "__main__":
    main()
