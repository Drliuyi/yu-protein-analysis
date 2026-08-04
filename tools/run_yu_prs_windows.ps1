param(
  [ValidateSet("help","preflight","prepare_gwas","score","merge_scores","associate","merge_associations","figure","report","all","monitor")]
  [string]$Mode = "help",
  [string]$Dir0 = "D:/UKB_data",
  [string]$AnalysisRoot = "",
  [string]$AnalysisProject = "yu_proteomic_repo_v3",
  [string]$RawProteinFile = "D:/UKB_data/phe/raw/prot_full_unimputed.tsv",
  [string]$PhenotypeRds = "D:/UKB_data/phe/Rdata/all.rds",
  [int]$Workers = 16,
  [int]$ScoreJobs = 2,
  [int]$AssociationJobs = 4,
  [int]$StartChr = 1,
  [int]$EndChr = 22,
  [int]$MemoryMb = 48000,
  [ValidateSet("Auto","DirectNas","StreamZspace")]
  [string]$GenotypeMode = "Auto",
  [string]$NasMountRoot = "/mnt/z/projects/genotype_pc_nas/imputed_pgen_autosomes",
  [string]$WindowsNasDrive = "Z:",
  [string]$WindowsNasRoot = "Z:/projects/genotype_pc_nas/imputed_pgen_autosomes",
  [switch]$Resume,
  [switch]$Force,
  [switch]$ConfirmHeavy,
  [switch]$KeepStreamedGenotype
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $PSScriptRoot
if (-not $AnalysisRoot) { $AnalysisRoot = Join-Path $Dir0 "analysis" }
$AnalysisDir = Join-Path $AnalysisRoot $AnalysisProject
$LogDir = Join-Path $AnalysisDir "00_logs"
$PrsDir = Join-Path $AnalysisDir "13_prs"
$RFile = Join-Path $ProjectDir "99_run_yu_prs.R"
$FullRFile = Join-Path $ProjectDir "99_run_yu_full_reproduction.R"
$WindowsScorer = Join-Path $ProjectDir "tools\score_prs_directnas_windows.py"
$ToolsBin = Join-Path $ProjectDir "tools\bin"
$Plink2Windows = Join-Path $ToolsBin "plink2.exe"
$PythonWindows = @(
  "C:/Users/Dr.Liuyi/AppData/Local/Programs/Python/Python312/python.exe",
  "C:/Users/Dr.Liuyi/anaconda3/envs/tf_gpu/python.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
$Rscript = @(
  "C:/Program Files/R/R-4.3.2/bin/x64/Rscript.exe",
  "C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Rscript) { throw "Rscript not found." }
if ($Mode -ne "monitor") {
  New-Item -ItemType Directory -Force -Path $LogDir, $PrsDir | Out-Null
}

function Convert-ToWslPath([string]$Path) {
  $value = (& wsl.exe wslpath -a ($Path -replace '\\','/')).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $value) { throw "Cannot convert to WSL path: $Path" }
  return $value
}

function Invoke-PrsR([string]$Stage, [string]$Endpoint = "all") {
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $log = Join-Path $LogDir ("prs_{0}_{1}.log" -f $Stage, $stamp)
  $argsList = @(
    "--vanilla", $RFile, "--mode=$Stage", "--dir0=$Dir0", "--analysis_root=$AnalysisRoot",
    "--analysis_project=$AnalysisProject", "--raw_protein_file=$RawProteinFile",
    "--phenotype_rds=$PhenotypeRds", "--endpoint_subset=$Endpoint", "--workers=$Workers"
  )
  if ($Resume) { $argsList += "--resume=true" }
  if ($Force) { $argsList += "--force=true" }
  Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | PRS R stage=$Stage | log=$log"
  $old = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  & $Rscript @argsList 2>&1 | Tee-Object -FilePath $log
  $code = $LASTEXITCODE
  $ErrorActionPreference = $old
  if ($code -ne 0) { throw "PRS R stage $Stage failed with exit code $code. See $log" }
}

function Invoke-PrsWsl([string]$ScriptName, [string]$GenotypeModeOverride = "") {
  $projectWsl = Convert-ToWslPath $ProjectDir
  $analysisWsl = Convert-ToWslPath $AnalysisDir
  $resumeValue = if ($Resume) { "1" } else { "0" }
  $cleanValue = if ($KeepStreamedGenotype) { "0" } else { "1" }
  $genotypeModeValue = if ($GenotypeModeOverride) { $GenotypeModeOverride } else { $GenotypeMode.ToLowerInvariant() }
  $scriptWsl = "$projectWsl/wsl/$ScriptName"
  Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | WSL stage=$ScriptName"
  $environment = @(
    "PROJECT_DIR=$projectWsl", "ANALYSIS_DIR=$analysisWsl",
    "THREADS=$Workers", "MEMORY_MB=$MemoryMb", "SCORE_JOBS=$ScoreJobs",
    "GENOTYPE_MODE=$genotypeModeValue", "DIRECT_NAS_ROOT=$NasMountRoot",
    "WINDOWS_NAS_DRIVE=$WindowsNasDrive",
    "START_CHR=$StartChr", "END_CHR=$EndChr",
    "RESUME=$resumeValue", "CLEAN_GENOTYPE=$cleanValue"
  )
  & wsl.exe env @environment bash $scriptWsl
  if ($LASTEXITCODE -ne 0) { throw "WSL stage $ScriptName failed with exit code $LASTEXITCODE." }
}

function Install-Plink2Windows {
  if (Test-Path $Plink2Windows) { return }
  New-Item -ItemType Directory -Force -Path $ToolsBin | Out-Null
  $zip = Join-Path $ToolsBin "plink2_win_avx2_20250129.zip"
  $extract = Join-Path $ToolsBin "plink2_win_avx2_20250129"
  $url = "https://s3.amazonaws.com/plink2-assets/alpha6/plink2_win_avx2_20250129.zip"
  Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Installing official PLINK2 Windows binary (about 7.5 MB)"
  Invoke-WebRequest -Uri $url -OutFile $zip
  if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
  Expand-Archive -Path $zip -DestinationPath $extract -Force
  $source = Get-ChildItem $extract -Filter "plink2.exe" -File -Recurse | Select-Object -First 1
  if (-not $source) { throw "Official PLINK2 archive did not contain plink2.exe." }
  Copy-Item $source.FullName $Plink2Windows -Force
  Remove-Item $zip -Force
  if (-not (Test-Path $Plink2Windows)) { throw "PLINK2 Windows installation failed." }
}

function Invoke-PrsDirectNas {
  if (-not $PythonWindows) { throw "Windows Python 3 was not found." }
  if (-not (Test-Path $WindowsScorer)) { throw "Missing Windows DirectNas scorer: $WindowsScorer" }
  $probe = Join-Path $WindowsNasRoot "chr1/pgen/chr1_imp.pgen"
  if (-not (Test-Path $probe)) {
    throw "Windows NAS root is not readable in this PowerShell session: $WindowsNasRoot. Confirm that Z: is connected in this same desktop session."
  }
  Install-Plink2Windows
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $log = Join-Path $LogDir ("prs_score_directnas_{0}.log" -f $stamp)
  $argsList = @(
    $WindowsScorer, "--project-dir", $ProjectDir, "--analysis-dir", $AnalysisDir,
    "--nas-root", $WindowsNasRoot, "--plink2", $Plink2Windows,
    "--workers", "$Workers", "--score-jobs", "$ScoreJobs", "--memory-mb", "$MemoryMb",
    "--start-chr", "$StartChr", "--end-chr", "$EndChr"
  )
  if ($Resume) { $argsList += "--resume" }
  Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Windows DirectNas PRS scoring | log=$log"
  $old = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  & $PythonWindows @argsList 2>&1 | Tee-Object -FilePath $log
  $code = $LASTEXITCODE
  $ErrorActionPreference = $old
  if ($code -ne 0) { throw "Windows DirectNas PRS scoring failed with exit code $code. See $log" }
}

function Invoke-PrsScore {
  $useDirectNas = $GenotypeMode -eq "DirectNas" -or ($GenotypeMode -eq "Auto" -and (Test-Path $WindowsNasRoot))
  if ($useDirectNas) {
    Invoke-PrsDirectNas
  } else {
    Invoke-PrsWsl "13_score_prs_stream.sh" "streamzspace"
  }
}

function Get-PrsEndpoints {
  $sourceFile = Join-Path $ProjectDir "config/prs_gwas_sources.tsv"
  return @((Import-Csv $sourceFile -Delimiter "`t").outcome_id)
}

function Invoke-PrsAssociations {
  if ($AssociationJobs -lt 1) { throw "AssociationJobs must be >= 1." }
  $endpoints = @(Get-PrsEndpoints)
  $jobs = [Math]::Min($AssociationJobs, $endpoints.Count)
  $shardWorkers = [Math]::Max(1, [Math]::Floor($Workers / $jobs))
  $queue = [System.Collections.Generic.Queue[string]]::new()
  foreach ($endpoint in $endpoints) { $queue.Enqueue($endpoint) }
  $running = @()
  $failures = @()
  Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | PRS regressions endpoints=$($endpoints.Count) concurrent=$jobs threads_per_shard=$shardWorkers"

  while ($queue.Count -gt 0 -or $running.Count -gt 0) {
    while ($queue.Count -gt 0 -and $running.Count -lt $jobs) {
      $endpoint = $queue.Dequeue()
      $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
      $stdout = Join-Path $LogDir ("prs_associate_{0}_{1}.out.log" -f $endpoint, $stamp)
      $stderr = Join-Path $LogDir ("prs_associate_{0}_{1}.err.log" -f $endpoint, $stamp)
      $argsList = @(
        "--vanilla", $RFile, "--mode=associate_shard", "--dir0=$Dir0", "--analysis_root=$AnalysisRoot",
        "--analysis_project=$AnalysisProject", "--raw_protein_file=$RawProteinFile",
        "--phenotype_rds=$PhenotypeRds", "--endpoint_subset=$endpoint", "--workers=$shardWorkers"
      )
      if ($Resume) { $argsList += "--resume=true" }
      if ($Force) { $argsList += "--force=true" }
      $process = Start-Process -FilePath $Rscript -ArgumentList $argsList `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
      $resultFile = Join-Path $PrsDir ("prs_protein_associations_{0}.csv.gz" -f $endpoint)
      $doneFile = Join-Path $PrsDir ("prs_association_{0}.done.json" -f $endpoint)
      $running += [pscustomobject]@{
        Endpoint=$endpoint; Process=$process; Stdout=$stdout; Stderr=$stderr;
        ResultFile=$resultFile; DoneFile=$doneFile; Started=Get-Date
      }
      Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | START PRS regression endpoint=$endpoint PID=$($process.Id)"
    }
    Start-Sleep -Seconds 2
    $next = @()
    foreach ($item in $running) {
      $item.Process.Refresh()
      if ($item.Process.HasExited) {
        $item.Process.WaitForExit()
        $exitCode = [int]$item.Process.ExitCode
        $doneStatus = $null
        if (Test-Path $item.DoneFile) {
          try { $doneStatus = (Get-Content $item.DoneFile -Raw | ConvertFrom-Json).status } catch { $doneStatus = "INVALID" }
        }
        if ($exitCode -ne 0 -or $doneStatus -ne "PASS" -or -not (Test-Path $item.ResultFile)) {
          $failures += $item
          Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | ERROR PRS regression endpoint=$($item.Endpoint) exit=$exitCode status=$doneStatus stderr=$($item.Stderr)"
        } else {
          $elapsed = [Math]::Round(((Get-Date) - $item.Started).TotalMinutes, 1)
          Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | DONE PRS regression endpoint=$($item.Endpoint) minutes=$elapsed"
        }
      } else {
        $next += $item
      }
    }
    $running = $next
  }
  if ($failures.Count -gt 0) {
    throw "PRS association shards failed: $($failures.Endpoint -join ', '). Successful shards are retained for -Resume."
  }
}

function Invoke-PrsFigure {
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $log = Join-Path $LogDir ("prs_figure_{0}.log" -f $stamp)
  $argsList = @(
    "--vanilla", $FullRFile, "--mode=figures", "--dir0=$Dir0", "--analysis_root=$AnalysisRoot",
    "--analysis_project=$AnalysisProject", "--raw_protein_file=$RawProteinFile",
    "--phenotype_rds=$PhenotypeRds", "--endpoint_subset=all", "--workers=$Workers",
    "--yys_mode=off", "--prediction_panel_mode=local_reselected"
  )
  & $Rscript @argsList 2>&1 | Tee-Object -FilePath $log
  if ($LASTEXITCODE -ne 0) { throw "Figure stage failed. See $log" }
}

function Show-PrsMonitor {
  Write-Host "Analysis: $AnalysisDir"
  Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -and $_.CommandLine -match "99_run_yu_prs|score_prs_directnas_windows|13_score_prs_(stream|directnas)|plink2" } |
    Select-Object ProcessId, Name, CreationDate, CommandLine | Format-Table -AutoSize
  foreach ($file in @("gwas_prepare_status.tsv", "score_status.tsv", "score_variant_counts.tsv", "prs_association_summary.csv")) {
    $path = Join-Path $PrsDir $file
    if (Test-Path $path) {
      Write-Host "`n== $file =="
      Get-Content $path -Tail 20
    }
  }
  Write-Host "`nAssociation shards: $(@(Get-ChildItem $PrsDir -Filter 'prs_protein_associations_*.csv.gz' -ErrorAction SilentlyContinue).Count) / 13"
}

function Show-PrsHelp {
  Write-Host @"
Yu/Chen PRS-protein local reconstruction

Stages:
  preflight           Validate local cohort/proteins and freeze target EIDs. Quick.
  prepare_gwas        Download and normalize 13 public GWAS sources. Network stage.
  score               Calculate 65 PRSs. Per chromosome, all incomplete outcome x threshold columns are scored in one PGEN scan. Heavy; requires -ConfirmHeavy.
  merge_scores        Sum chromosome scores and QC 13 outcomes x 5 thresholds.
  associate           Run 13 outcome-specific protein regressions; all significant and non-significant rows retained.
  merge_associations  Enforce the complete five-threshold matrix and prepare Figure 6A source data.
  figure              Draw Figure 6A from local complete results; stars only Bonferroni-significant cells.
  report              Write source/QC/result summary.
  all                 Run every stage in order; requires -ConfirmHeavy.
  monitor             Read-only progress display.

Important:
  The beta/effect-allele columns from the article-cited GWAS are the reference weights.
  The article did not publish its final per-SNP PRS files or complete clumping command.
  Therefore results are labelled article-source reconstruction, not exact author-weight replication.
  -GenotypeMode Auto|DirectNas|StreamZspace controls genotype access; Auto is recommended.
  -GenotypeMode DirectNas runs Windows PLINK2 directly against -WindowsNasRoot (default Z:/projects/...). It does not mount Z: in WSL and does not copy genotypes to D:.
  -ScoreJobs controls concurrent chromosome jobs for DirectNas (default 2). With -Workers 16 and -MemoryMb 48000, each receives 8 threads and 24000 MB.
  StreamZspace always uses one chromosome job because each chromosome is copied to D-drive scratch.
"@
}

if ($Mode -eq "help") { Show-PrsHelp; exit 0 }
if ($Mode -eq "monitor") { Show-PrsMonitor; exit 0 }
if ($ScoreJobs -lt 1) { throw "ScoreJobs must be >= 1." }
if ($Mode -in @("score", "all") -and -not $ConfirmHeavy) {
  throw "Mode $Mode streams chromosome genotypes and is compute intensive. Re-run with -ConfirmHeavy after reviewing preflight."
}

switch ($Mode) {
  "preflight" { Invoke-PrsR "preflight" }
  "prepare_gwas" { Invoke-PrsWsl "13_prepare_prs_gwas.sh" }
  "score" { Invoke-PrsScore }
  "merge_scores" { Invoke-PrsR "merge_scores" }
  "associate" { Invoke-PrsAssociations }
  "merge_associations" { Invoke-PrsR "merge_associations" }
  "figure" { Invoke-PrsFigure }
  "report" { Invoke-PrsR "report" }
  "all" {
    Invoke-PrsR "preflight"
    Invoke-PrsWsl "13_prepare_prs_gwas.sh"
    Invoke-PrsScore
    Invoke-PrsR "merge_scores"
    Invoke-PrsAssociations
    Invoke-PrsR "merge_associations"
    Invoke-PrsFigure
    Invoke-PrsR "report"
  }
}
