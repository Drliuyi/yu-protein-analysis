param(
  [ValidateSet("help","preflight","prepare","train","evaluate","report","all")][string]$Mode="help",
  [string]$Dir0="D:/",
  [string]$AnalysisRoot="",
  [string]$AnalysisProject="yy_cad_yu_yys_legacy257",
  [string]$RawProteinFile="D:/data/ukb/phe/raw/prot_full_unimputed.tsv",
  [string]$PhenotypeRds="D:/data/ukb/phe/Rdata/all.rds",
  [string]$PanelMappingFile="D:/data.BIG/gwas/ppp/olink_protein_map_3k_v1.tsv",
  [int]$Workers=16,
  [int]$BootstrapN=1000,
  [switch]$Resume,
  [switch]$Force
)

$CodeDir=Split-Path -Parent $PSScriptRoot
$ProjectDir=Split-Path -Parent $CodeDir
$RFile=Join-Path $ProjectDir "f/entry/99_run_yu_yys.R"
$Config=Join-Path $ProjectDir "f/config/defaults.json"
if(-not $AnalysisRoot){$AnalysisRoot=Join-Path $Dir0 "analysis"}
$AnalysisDir=Join-Path $AnalysisRoot $AnalysisProject
$LogDir=Join-Path $AnalysisDir "00_logs"; New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Rscript=@("C:/Program Files/R/R-4.3.2/bin/x64/Rscript.exe","C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe") | Where-Object {Test-Path $_} | Select-Object -First 1
$Python=@("C:/Users/Dr.Liuyi/anaconda3/envs/tf_gpu/python.exe","C:/Users/Dr.Liuyi/anaconda3/python.exe") | Where-Object {Test-Path $_} | Select-Object -First 1
if(-not $Rscript){throw "Rscript not found"}; if(-not $Python){throw "Python with lightgbm not found"}

function Invoke-RStage([string]$Stage){
  $log=Join-Path $LogDir ("{0}_{1}.log" -f $Stage,(Get-Date -Format "yyyyMMdd_HHmmss"))
  $args=@("--vanilla",$RFile,"--mode=$Stage","--dir0=$Dir0","--analysis_root=$AnalysisRoot","--analysis_project=$AnalysisProject","--raw_protein_file=$RawProteinFile","--phenotype_rds=$PhenotypeRds","--panel_mapping_file=$PanelMappingFile","--workers=$Workers","--bootstrap_n=$BootstrapN")
  if($Resume){$args+="--resume=true"}; if($Force){$args+="--force=true"}
  Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | R stage=$Stage | log=$log"
  $old=$ErrorActionPreference; $ErrorActionPreference="Continue"; & $Rscript @args 2>&1 | Tee-Object -FilePath $log; $code=$LASTEXITCODE; $ErrorActionPreference=$old
  if($code -ne 0){throw "R stage $Stage failed with exit code $code. See $log"}
}
function Invoke-Train {
  $log=Join-Path $LogDir ("train_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss")); $py=Join-Path $ProjectDir "f/python/02_train_lightgbm.py"
  $args=@($py,"--analysis-dir",$AnalysisDir,"--config",$Config,"--workers",$Workers); if($Resume){$args+="--resume"}
  Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Python LightGBM | log=$log"
  $old=$ErrorActionPreference; $ErrorActionPreference="Continue"; & $Python @args 2>&1 | Tee-Object -FilePath $log; $code=$LASTEXITCODE; $ErrorActionPreference=$old
  if($code -ne 0){throw "Python train failed with exit code $code. See $log"}
}

if($Mode -eq "help"){Invoke-RStage "help"; exit 0}
switch($Mode){
  "preflight" {Invoke-RStage "preflight"}
  "prepare" {Invoke-RStage "prepare"}
  "train" {Invoke-Train}
  "evaluate" {Invoke-RStage "evaluate"}
  "report" {Invoke-RStage "report"}
  "all" {Invoke-RStage "preflight"; Invoke-RStage "prepare"; Invoke-Train; Invoke-RStage "evaluate"; Invoke-RStage "report"}
}
Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | COMPLETE mode=$Mode | analysis=$AnalysisDir"
