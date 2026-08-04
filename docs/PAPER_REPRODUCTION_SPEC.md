# Yu/Chen 2025 source-locked reproduction specification

## Scope

The reproduction track follows the published analysis order:

1. Define 53,026-style UKB-PPP baseline cohort and 14 CVD endpoints.
2. Retain baseline Olink proteins with missingness no greater than 30%.
3. Exclude participants with any of the 14 CVDs at baseline for incident
   analyses.
4. Run adjusted Cox models for every protein and every incident endpoint.
5. Split the incident cohort into a two-thirds derivation set and one-third
   untouched test set.
6. Within derivation only, repeat protein association screening and retain the
   union passing `P < 0.05 / number_of_retained_proteins` across endpoints.
7. Fit preliminary LightGBM classifiers per endpoint, rank normalized gain,
   and select the smallest prefix whose cumulative gain reaches 30%.
8. Take the union of endpoint-specific selected proteins. The paper reported
   257 proteins; the local count is an audit result, not a hard-coded target.
9. Fit SCORE2, Protein, and SCORE2+Protein LightGBM models for all endpoints.
   Protein `NA` values remain `NA` and use LightGBM's native missing-value
   routing. A cohort EID absent from the raw protein table is a hard error;
   participants whose requested panel is entirely missing are retained and
   enumerated in split-specific QC files rather than silently removed.
10. Evaluate the locked hold-out set with paired AUC comparisons and 1,000
    participant-level bootstrap replicates.
11. Add YYScore as a paired extension only after the standard Yu/Chen benchmark
    has been reproduced and frozen.

## Published anchors

- Proteomics cohort: 53,026.
- Raw unique proteins: 2,923; retained after >30% protein-missingness exclusion:
  2,920.
- Incident-analysis cohort free of all baseline CVDs: 46,818.
- Participants developing at least one incident CVD: 9,096.
- Significant incident associations: 3,089 involving 892 unique proteins and
  13 outcomes.
- Derivation candidate union: 671 proteins.
- Final cross-endpoint prediction union: 257 proteins.
- Split: two-thirds derivation, one-third hold-out.
- LightGBM: 500 estimators, maximum depth 15, 10 leaves, row fraction 0.7,
  learning rate 0.01, feature fraction 0.7.
- Bootstrap: 1,000.

These values are diagnostic anchors, not forced outputs. Every deviation must
be explained using input version, phenotype definition, missingness, or the
unreported random split.

## Cox model

For protein `j` and outcome `k`:

```text
Surv(time_k, event_k) ~ z(protein_j)
  + age + sex + ethnicity + TDI
  + blood_collection_season
  + protein_measurement_to_sampling_days
  + fasting_time + SBP + BMI + smoking + alcohol
```

The supplement does not explicitly state whether Cox exposure units are raw
NPX or one SD. The implementation uses within-scope z-scores, stores the raw
mean and SD beside every estimate, and marks this decision as `REVIEW` in the
method-provenance table. It can therefore be audited without changing protein
selection P-values.

Significance is `P < 0.05 / P_QC`, where `P_QC` is the actual number of
retained local proteins. No fixed denominator is used when the local panel
differs from 2,920.

## CMR model

The local replacement for published Figure 3 uses the 19 cardiac MRI phenotypes
listed in `f/config/cmr_metrics.csv`. The source is the locally extracted UKB field
table `analysis/sleepchart_reproduction/data/mribag_features/heart/feature.tsv`.
It is joined to the current baseline-14-CVD-free proteomics cohort by EID. For each
metric and each protein in the exact Cox-retained panel:

```text
z(CMR_metric) ~ z(protein_j) + the same adjusted covariates
```

Participants with any baseline CVD are excluded. Missingness is handled per
protein-metric regression, and the multiplicity threshold is `0.05/P_QC` using the
actual shared local protein panel. The paper reported 4,287 participants, 19
metrics, and 441 proteins associated with 18 metrics; local sample size and signal
counts are expected to differ with the current UKB release and must be reported
from `07_cmr/cmr_summary.json` rather than copied from the publication.

## Prediction model

The published model is a binary LightGBM classifier for whether the endpoint
occurred during observed follow-up; it is not presented as a 1-, 3-, 5-, or
10-year time-dependent AUC model. The test-set AUC therefore must not be labelled
with a fixed horizon.

## YYScore extension

The standard benchmark and its YY extension use the same split, selected
protein union, endpoint, SCORE2 variable, LightGBM parameters, and bootstrap
indices. The paired design matrices may differ only by one `YYScore` column.
