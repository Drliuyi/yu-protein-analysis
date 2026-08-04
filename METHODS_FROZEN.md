# Frozen methods

## Current decision status

The accepted and frozen method is the full Yu/Chen reproduction described
below. All canonical runs use `YYScoreMode off`. The CAD YYScore extension is
retired after evaluation and is preserved only as a historical audit branch;
it is not part of the accepted Yu reproduction or manuscript evidence.

## Full 14-outcome source-locked benchmark

- Baseline UKB-PPP Olink Explore 3072 data.
- Proteins with missingness above 30% were excluded in the source study.
- Full-panel Cox associations are run for all 14 outcomes. Derivation-only
  Bonferroni-positive proteins enter endpoint-specific preliminary LightGBM;
  the cumulative 30% gain prefixes are unioned across outcomes.
- Participants with any of 14 baseline cardiovascular diseases are excluded.
- Random two-thirds derivation and one-third hold-out testing split.
- LightGBM: 500 estimators, depth 15, 10 leaves, row fraction 0.7, learning
  rate 0.01, feature fraction 0.7; ten-fold derivation diagnostics.
- Predictor sets: SCORE2, locally selected Protein union, and Protein+SCORE2.
- SCORE2 is calculated for the UK low-risk region and recalibrated by isotonic
  regression using derivation data only.
- Hold-out evaluation uses 1,000 participant-level bootstrap samples.

## Local operational decisions

- Follow-up cutoff is 2023-09-30.
- Local split seed is 20260715 because the publication does not report its split.
- CAD date is the minimum available date from the frozen local ICD10, ICD9, and
  OPCS CAD/MI sources.
- Protein missing values remain missing for LightGBM, which handles missingness
  natively. Training medians are used only to form standardized `YYScore257`.
- `subsample_freq=1` is explicit so the reported row fraction 0.7 is active.
- Classification thresholds are selected from derivation out-of-fold predictions
  by the Youden criterion and then frozen for the test set.

## Retired historical analysis: CAD-only YYScore extension

This section documents a retired analysis and must not be executed or cited as
part of the frozen Yu reproduction. ABCD used derivation participants and independent baseline prevalent-CAD Yang
cases only. No hold-out protein, event, follow-up, or performance is used.

```text
YYS_raw_j = (A_j * B_j * C_j * D_j)^(1/4)
YYS_j     = 0.05 + 0.95 * rank_norm(YYS_raw_j)
w_j       = sign(Yang-control contrast_j) * YYS_j
YYScore_i = sum_j(w_j * Z_ij)
```

The score is built from exactly the same locally selected cross-outcome protein
union that enters the paired benchmark. The two extension comparisons are
`Protein+YYScore` versus `Protein` and `Protein+SCORE2+YYScore` versus
`Protein+SCORE2`; each design matrix differs by exactly one column. It adds a
structured low-dimensional direction, not new measured biomarkers. The
extension is CAD-only because its Yang auxiliary cases are prevalent CAD.

ABCD components must pass missingness, variability, boundary-saturation and
pairwise-correlation gates before any hold-out prediction is generated. A failed
component is not removed or reweighted after test inspection.

## Reproducibility boundary

The article did not release author scripts, split EIDs or the LightGBM tuning
search space. This is an independent source-locked implementation using the
reported final parameters. Every published, inferred and local computational
decision is listed in `config/method_provenance.csv`.
