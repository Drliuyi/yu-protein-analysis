# Yu Protein Analysis

Yu/Chen 2025 plasma-proteomics article reproduction and local extension for
incident cardiovascular outcomes. The frozen main workflow uses
`YYScoreMode=off`; historical YYScore code remains in `f/` for audit only.

## One command

The project exposes equivalent PowerShell and WSL/Git Bash entry points:

```powershell
.\yu.ps1 -Step install
.\yu.ps1 -Step setup
.\yu.ps1 -Step doctor
.\yu.ps1 -Step all -ConfirmHeavy -Resume
```

```bash
./yu.sh install
./yu.sh setup
./yu.sh doctor
./yu.sh all --confirm-heavy --resume
```

Useful commands:

```powershell
.\yu.ps1 -Step help       # list steps, parameters, diseases and resources
.\yu.ps1 -Step install    # install frozen Python 3.9 and all required R packages
.\yu.ps1 -Step setup      # resolve paths, save them, do not run analysis
.\yu.ps1 -Step doctor     # fail-fast check before computation
.\yu.ps1 -Step paths      # show current defaults and saved path profile
.\yu.ps1 -Step status     # read-only progress check
.\yu.ps1 -Step finalize   # build and verify the complete Figure 1-6 package
.\yu.ps1 -Step package    # create source ZIP and SHA256 manifest
```

Shell equivalents include `./yu.sh setup`, `./yu.sh status`,
`./yu.sh figures --force`, and `./yu.sh --help`. The shell file is a thin
wrapper around `yu.ps1`; it does not contain a second analysis implementation.

`-Step` accepts one number, lists (`"1,3,4"`), ranges (`"1-4"`), `core`,
`downstream`, `all`, `figures`, `finalize`, `doctor`, `install`, `package`,
`setup`, `paths`, and `status`.

`all` runs the complete local analysis. `finalize` requires completed Steps
1-10 and refuses to report success unless Figures 1-6 exist as non-empty PDF,
PNG and TIFF files together with `RESULTS_AND_QC.md`.

## Paths

Defaults follow the Huang-lab [`jielab/pub`](https://github.com/jielab/pub)
D-drive interface:

| Role | Default |
|---|---|
| logical root | `D:/` |
| phenotype root | `D:/data/ukb/phe` |
| script root | `D:/scripts` |
| analysis root | `D:/analysis` |
| project entry | the folder containing `yu.ps1` |
| genotype root | `Z:/projects/genotype_pc_nas/imputed_pgen_autosomes` |

The existing WinPC `D:/UKB_data` tree does not need to be moved. If a required
Huang-style path is absent, `yu.ps1` opens a Windows file/folder picker; an SSH
session uses a console prompt. Confirmed paths are stored in:

```text
%LOCALAPPDATA%/YuProteinAnalysis/paths.json
```

Later runs reuse this profile. Command arguments and `YU_*` environment
variables take precedence. Use `-ResetPaths` to rebuild the profile or
`-PathPromptMode Off` for a non-interactive job that must fail immediately on a
missing path.

Runtime overrides are `YU_RSCRIPT`, `YU_PYTHON` and `YU_CONDA`, or the matching
`-RscriptExe`, `-PythonExe` and `-CondaExe` options. No user-account path is
hard-coded.

## Layout

```text
yu.ps1                  PowerShell public command
yu.sh                   WSL/Git Bash public command
f/
  entry/                R entry points
  R/                    analysis and figure code
  python/               model code
  tools/                Windows orchestration and utilities
  wsl/                  PRS shell stages
  config/               frozen endpoints, mappings and parameters
  tests/                static and smoke tests
docs/                   methods, QC and operational notes
references/             article supplements and source manifests
.github/workflows/       automated shell, PowerShell, Python and R checks
```

Only `yu.ps1` and `yu.sh` are intended for routine project operation. Files
under `f/` are implementation details and remain directly callable for
debugging and audit.

## Main steps

| Step | Analysis |
|---:|---|
| 1 | source audit and preflight |
| 2 | incident CVD cohort |
| 3 | full-panel Cox associations |
| 4 | local protein selection, LightGBM prediction and hold-out evaluation |
| 5 | CMR associations |
| 6 | Mendelian randomization |
| 7 | mediation candidate analysis |
| 8 | CMAverse mediation |
| 9 | 13-outcome PRS-protein reconstruction |
| 10 | enrichment, TF and STRING-PPI analyses |
| 11 | final Figures 1-6 and report |

Steps 8 and 9 require `-ConfirmHeavy`. `-Resume` reuses valid markers and
completed shards. Alternate diseases or protein panels must use a new
`-AnalysisProject`; the frozen `yu_proteomic_repo_v3` tree is protected.

The official open-access supplementary workbook and methods PDF required by
the workflow are included and checksum-audited. UKB participant data, genotype,
pQTL resources and the Olink processing-date file are not distributed; setup
requests their local locations and records them in the machine-local profile.

## Scientific boundaries

- The local prediction panel is selected only from derivation data.
- Hold-out outcomes do not enter protein selection or model tuning.
- Local counts are reported, not forced to published counts.
- Official-table redraws and locally recomputed evidence are labelled separately.
- The canonical workflow does not add ABCD-YYS or unrelated model families.
- Individual-level UKB, genotype and analysis outputs are never included in the repository package.

Detailed usage is in [docs/STEP_RUNNER_ZH.md](docs/STEP_RUNNER_ZH.md). Frozen
methods and result interpretation boundaries are in
[METHODS_FROZEN.md](METHODS_FROZEN.md) and
[QC_REVIEW_CHECKLIST.md](QC_REVIEW_CHECKLIST.md).
