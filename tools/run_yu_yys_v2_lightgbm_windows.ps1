param(
  [ValidateSet('inputs','prepare','train','evaluate','all','status','help')]
  [string]$Mode = 'help',
  [string]$Dir0 = 'D:/UKB_data',
  [string]$AnalysisProject = 'yu_proteomic_repo_cad_yysv2_20260721',
  [string]$InputDir = '',
  [int]$Workers = 16,
  [int]$ModelJobs = 3,
  [int]$SplitSeed = 20260715,
  [int]$InnerSeed = 20260716,
  [int]$Seed = 20260721,
  [switch]$Resume
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Join-Path $Dir0 'scripts/yy_cad_yu_yys'
$Phase3BProject = Join-Path $Dir0 'scripts/yy_cad_phase3B_sparse_yys_prediction'
$AnalysisDir = Join-Path $Dir0 "analysis/$AnalysisProject"
if (-not $InputDir) { $InputDir = Join-Path $AnalysisDir '00_inputs' }
$CacheDir = Join-Path $AnalysisDir '01_cache'
$LogDir = Join-Path $AnalysisDir '00_logs'
$Rscript = 'C:/Program Files/R/R-4.3.2/bin/x64/Rscript.exe'
$Python = 'C:/Users/Dr.Liuyi/anaconda3/envs/yu_proteomic_repo_py39/python.exe'

if ($Mode -eq 'help') {
  @'
Our CAD outcome: Yu-style LightGBM plus matched YinScore/ABCD-YYS v2

Modes:
  inputs    Split our CAD cohort into 2/3 derivation and 1/3 hold-out; compute
            derivation-only ProtWAS and ABCD-YYS v2. Ten inner folds are saved.
  prepare   Align prot.rds and create a reusable 37,127 x 2,910 float32 cache.
  train     Derivation Bonferroni screen -> preliminary LightGBM -> cumulative
            30% gain panel -> final panel, +YinScore, and +YYScore models.
  evaluate  Hold-out AUC/PR-AUC/Brier, 1/3/5/10-year AUC, C-index,
            calibration, paired DeLong comparisons, and hard QC.
  all       inputs -> prepare -> train -> evaluate.
  status    Show active processes and generated outputs.

No published Yu panel, fixed Yu outcome, fixed Yu split, permutation control,
or other model family is used. The matched YinScore and YYScore models use the
same CAD protein panel and the same number of predictors.
'@ | Write-Output
  exit 0
}

New-Item -ItemType Directory -Force -Path $AnalysisDir,$InputDir,$CacheDir,$LogDir | Out-Null
if (-not (Test-Path $Rscript)) { throw "Rscript not found: $Rscript" }
if (-not (Test-Path $Python)) { throw "Frozen Yu Python not found: $Python" }

function Run-Stage([string]$Stage) {
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $log = Join-Path $LogDir "${Stage}_${stamp}.log"
  if ($Stage -eq 'inputs') {
    $marker = Join-Path $InputDir 'input_manifest.csv'
    if ($Resume -and (Test-Path $marker)) { Write-Output "Resume: inputs already complete"; return }
    & $Rscript --vanilla (Join-Path $ProjectDir 'tools/prepare_yys_v2_lightgbm_inputs.R') `
      "--phase1_cache=$Dir0/analysis/yy_cad_phase1_protwas_20260719/cache/phase1_analysis_data.rds" `
      "--phase3b_project=$Phase3BProject" "--out_dir=$InputDir" "--workers=$Workers" `
      "--split_seed=$SplitSeed" "--inner_seed=$InnerSeed" 2>&1 | Tee-Object -FilePath $log
  } elseif ($Stage -eq 'prepare') {
    $marker = Join-Path $CacheDir 'matrix_manifest.csv'
    if ($Resume -and (Test-Path $marker)) { Write-Output "Resume: prepare already complete"; return }
    & $Rscript --vanilla (Join-Path $ProjectDir 'tools/prepare_yys_v2_lightgbm_matrix.R') `
      "--prot_rds=$Dir0/phe/Rdata/prot.rds" "--input_dir=$InputDir" `
      "--cache_dir=$CacheDir" 2>&1 | Tee-Object -FilePath $log
  } elseif ($Stage -eq 'train') {
    $marker = Join-Path $AnalysisDir '02_lightgbm/training_manifest.json'
    if ($Resume -and (Test-Path $marker)) { Write-Output "Resume: train already complete"; return }
    & $Python (Join-Path $ProjectDir 'python/09_yys_v2_lightgbm.py') `
      --analysis-dir $AnalysisDir --input-dir $InputDir --workers $Workers `
      --model-jobs $ModelJobs --seed $Seed 2>&1 | Tee-Object -FilePath $log
  } elseif ($Stage -eq 'evaluate') {
    & $Rscript --vanilla (Join-Path $ProjectDir 'tools/evaluate_yys_v2_lightgbm.R') `
      "--analysis-dir=$AnalysisDir" 2>&1 | Tee-Object -FilePath $log
  }
  if ($LASTEXITCODE -ne 0) { throw "Stage $Stage failed with exit code $LASTEXITCODE. See $log" }
}

if ($Mode -eq 'status') {
  Write-Output "Analysis: $AnalysisDir"
  Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -match '09_yys_v2_lightgbm|prepare_yys_v2_lightgbm'
  } | Select-Object ProcessId,Name,CreationDate,CommandLine | Format-List
  Get-ChildItem (Join-Path $AnalysisDir '02_lightgbm') -ErrorAction SilentlyContinue |
    Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize
  exit 0
}

switch ($Mode) {
  'inputs'   { Run-Stage 'inputs' }
  'prepare'  { Run-Stage 'prepare' }
  'train'    { Run-Stage 'train' }
  'evaluate' { Run-Stage 'evaluate' }
  'all'      { Run-Stage 'inputs'; Run-Stage 'prepare'; Run-Stage 'train'; Run-Stage 'evaluate' }
}
