# Yu/Chen 2025 reproduction

> **Frozen scope, 2026-07-21:** the accepted project is the Yu/Chen article
> reproduction with `-YYScoreMode off`. YYScore and ABCD-YYS analyses are
> retired and retained only for historical audit. They are not part of the
> canonical model set, figures, tables, report, or manuscript conclusions.

This repository contains two deliberately separated tracks for
"Systematic analyses uncover plasma proteins linked to incident cardiovascular
diseases" (Chen et al., Protein & Cell, DOI 10.1093/procel/pwaf072).

No author analysis repository was found. The article's code-availability
statement lists software and versions, but not scripts, split EIDs or fitted
models. This is therefore a source-locked independent implementation.

## Track A: full article reproduction

Entry point: `tools/run_yu_full_reproduction_windows.ps1`.

For routine use, prefer the step-based orchestrator:

```powershell
cd D:\UKB_data\scripts\yy_cad_yu_yys
.\yu.ps1 `
  -Step "1-4" `
  -AnalysisProject yu_proteomic_repo_v3 `
  -Workers 16 -CoxJobs 4 -ModelJobs 3 `
  -Resume
```

It accepts one step, comma-separated steps, ranges, `core`, `downstream`,
`all`, `status`, and `-PlanOnly`. It calls the existing validated full and PRS
runners and does not reimplement statistical code. The canonical step runner
always fixes `YYScoreMode=off`. See `docs/STEP_RUNNER_ZH.md`.

The WinPC defaults are the user's existing physical layout under
`D:/UKB_data`, with analysis outputs under `D:/UKB_data/analysis` and direct
genotype reads from `Z:/projects/genotype_pc_nas/imputed_pgen_autosomes`.
When a required path is absent, the unified runner opens a Windows file/folder
picker; SSH sessions use a console prompt. Lower-level runners remain
non-interactive. Use `-PathPromptMode Off` for unattended jobs.

Disease-specific prediction and selectable model-protein panels are available
through `-Disease`, `-ProteinPanel`, `-ModelProteinFile`, and `-ModelProteins`.
Every alternate endpoint/panel analysis must use a new `-AnalysisProject`; the
frozen `yu_proteomic_repo_v3` result tree is protected from these overrides.

It implements the participant-level modules that can be recreated locally:

1. official supplement and method audit;
2. 14-outcome incident cohort and frozen two-thirds/one-third split;
3. full Olink panel Cox associations;
4. derivation-only Bonferroni candidate union;
5. preliminary LightGBM normalized-gain selection to cumulative 30%;
6. cross-endpoint protein union;
7. SCORE2, Protein and Protein+SCORE2 LightGBM benchmarks;
8. locked hold-out metrics, DeLong, NRI/IDI and 1,000 paired bootstraps;
9. publication figures in PDF, 600-dpi TIFF and PNG with source data.

The default `-YYScoreMode off` runs only the source-locked Yu/Chen reproduction.
The optional `-YYScoreMode on` additionally builds a CAD-only ABCD-YYS score
without hold-out outcomes and fits paired models that differ from their
benchmark by one `YYScore` column.

CMR, MR, PRS and mediation stages are explicitly gated until their
participant-level or external summary-statistic inputs are supplied. Figure 6B-D
systems biology is implemented in code from the local Cox results using the
version-locked MSigDB 2026.1 gene sets, STRING v12 API and downloaded TRRUST v2
human relationships.
Official-table reconstructions are named `reference_*` and are never presented
as locally recomputed evidence.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run_yu_full_reproduction_windows.ps1 `
  -Mode help
```

Modes include `sources`, `preflight`, `cohort`, `cox_prepare`, `cox_shard`,
`cox_merge`, `cox_parallel`, `select`, `yys`, `train`, `evaluate`, `figures`,
`systems_prepare`, `systems_enrichment`, `systems_tf`, `systems_ppi`,
`systems_figures`, `figure6_systems`, `report`, `monitor`, `all`, and `all_fast`.

Generate Figure 6B-D after `cox_merge` has completed and combine them with the
existing local Figure 6A in the article-matched left-column/right-stack layout:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run_yu_full_reproduction_windows.ps1 `
  -Mode figure6_systems `
  -Dir0 D:/UKB_data `
  -AnalysisProject yu_proteomic_repo_v3 `
  -StringRequiredScore 700 `
  -SystemsTopN 15 `
  -SystemsMaxTf 46 `
  -SystemsFdr 0.05 `
  -Resume
```

The wrapper checks the required R packages and installs only missing CRAN
packages before these systems modes start.

Figure 6A is included only as the left visual panel. Its PRS proteins do not
enter the Figure 6B-D calculations. The systems foreground is the union of
locally Bonferroni-significant full-incident Cox proteins; its enrichment
background is the locally measured Olink panel. See
`docs/FIGURE6_SYSTEMS_CODE_IMPLEMENTATION_ZH.md` for the frozen methods and
the exact distinction from the article's unavailable Metascape/Cytoscape sessions.

On the 16-core/32-thread WinPC, the frozen fast schedule is:

- four independent Cox endpoint processes;
- three concurrent LightGBM model fits with five threads per fit;
- no PSOCK cluster and no nested 16-thread model processes.

`all_fast` is resumable and never stops unrelated R/Python jobs. `monitor` is
read-only.

Run the article reproduction first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run_yu_full_reproduction_windows.ps1 `
  -Mode all_fast `
  -Dir0 D:/UKB_data `
  -AnalysisProject yu_proteomic_repo_v2 `
  -RawProteinFile D:/UKB_data/phe/raw/prot_full_unimputed.tsv `
  -Workers 16 -CoxJobs 4 -ModelJobs 3 -BootstrapN 1000 `
  -YYScoreMode off `
  -Resume
```

Only after freezing and reviewing that benchmark, the same command can be
rerun with `-YYScoreMode on -Resume`. Completed source, cohort, Cox and protein
selection stages are reused; the CAD YYScore, paired models, evaluation,
figures and report are then rebuilt under the explicit extension mode.

The default output is `D:/UKB_data/analysis/yy_cad_yu_yys`.
Formal work requires an **unimputed baseline NPX table** supplied through
`-RawProteinFile`; the existing pre-imputed `prot.rds` must not silently replace
that input.

## Track B: legacy fixed published CAD-257 benchmark

This is a **Yu/Chen-style local implementation using the published fixed
257-protein panel**. It is not a literal replication because the publication did
not release the original participant split, exact assay-level table, or all
software defaults.

This retained legacy audit predates the full 14-outcome local selection. It uses
the published fixed 257-protein panel. Its five
frozen models are:

1. `Yu_SCORE2`
2. `Yu_Protein257`
3. `Yu_SCORE2_Protein257`
4. `Yu_Protein257_plus_YYScore257`
5. `Yu_SCORE2_Protein257_plus_YYScore257`

The primary comparison is model 5 versus model 3. The secondary comparison is
model 4 versus model 2. In each pair, measured proteins, participants, split,
folds, and LightGBM parameters are identical; only `YYScore257` is added.

Entry point:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run_yu_yys_windows.ps1 `
  -Mode help
```

Stages: `preflight`, `prepare`, `train`, `evaluate`, `report`, `all`.
Its default output is `D:/UKB_data/analysis/yy_cad_yu_yys_legacy257`, so it
cannot overwrite the full reproduction.

No stage reads old FairK, v1r, v2, v3, or Pradeep model outputs.

## Archived pre-existing WinPC implementation

The WinPC scripts retrieved on 2026-07-15 are preserved unchanged under
`legacy/ukbppp_cardiac_diseases_reproduction_20260715`. They use Cox models
plus logistic LASSO prediction and can default to an Explore 1536-like panel.
They are retained only for provenance and code comparison: neither full-track
entry point sources them, and their outputs are not accepted by the current
selection, YYScore, evaluation, report, or figure stages.

## Scientific guardrails

- The paper's prediction AUC is event/no-event classification across observed
  follow-up, not a fixed 1/3/5/10-year AUC.
- Only an all-14-endpoint run can be compared with the published anchors of 671
  candidate and 257 final proteins.
- Test-set outcomes are never used for selection or model tuning.
- Local counts are diagnostic outputs, not forced to 2,920, 671 or 257.
- The standard Yu/Chen benchmark is frozen before a paired YYScore extension is
  interpreted.
- CAD-derived YYS is never applied to the other 13 outcomes.
- The paper reports final LightGBM hyperparameters but not its complete tuning
  search space; this implementation freezes the reported values and labels that
  limitation rather than claiming line-for-line author-code replication.
