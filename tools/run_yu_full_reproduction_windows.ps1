param(
  [ValidateSet("help","sources","preflight","cohort","cox_prepare","cox_shard","cox_merge","cox","cox_parallel","cmr_prepare","cmr_shard","cmr_merge","cmr","cmr_parallel","mr_prepare","mr_run","mediation_prepare","mediation_run","mediation_cmest_pilot","mediation_cmest_shard","mediation_cmest_merge","mediation_cmest_parallel","figure5_local","systems_prepare","systems_enrichment","systems_tf","systems_ppi","systems_figures","figure6_systems","select","yys","train","evaluate","figures","report","monitor","all","all_fast")]
  [string]$Mode = "help",
  [string]$Dir0 = "D:/UKB_data",
  [string]$AnalysisRoot = "",
  [string]$AnalysisProject = "yy_cad_yu_yys",
  [string]$RawProteinFile = "D:/UKB_data/phe/raw/prot_full_unimputed.tsv",
  [string]$CmrFeatureFile = "D:/UKB_data/analysis/sleepchart_reproduction/data/mribag_features/heart/feature.tsv",
  [string]$PhenotypeRds = "D:/UKB_data/phe/Rdata/all.rds",
  [string]$RawPhenotypeFile = "D:/UKB_data/pheno.tsv.gz",
  [string]$PanelMappingFile = "D:/UKB_data/ppp/map.raw/olink_protein_map_3k_v1.tsv",
  [string]$PqtlRoot = "D:/UKB_data/ppp/clean",
  [string]$MrOutcomeLookupDir = "",
  [string]$OlinkProcessingStartDateFile = "",
  [string]$EndpointSubset = "all",
  [int]$Workers = 16,
  [int]$CoxJobs = 4,
  [int]$CmrJobs = 4,
  [string]$CmrMetricSubset = "all",
  [int]$ModelJobs = 3,
  [int]$BootstrapN = 1000,
  [int]$CmestJobs = 8,
  [int]$CmestShardIndex = 1,
  [int]$CmestShardCount = 1,
  [int]$CmestPilotBoot = 20,
  [int]$StringRequiredScore = 700,
  [int]$SystemsTopN = 15,
  [int]$SystemsMaxTf = 46,
  [double]$SystemsFdr = 0.05,
  [ValidateSet("published_257","local_reselected","custom")]
  [string]$PredictionPanelMode = "local_reselected",
  [string]$CustomProteinPanelFile = "",
  [string]$CustomProteins = "",
  [string]$Figure4ExtraProject = "",
  [string]$Figure4ExtraOutcome = "",
  [string]$Figure4ExtraLabel = "",
  [string]$PythonExe = "",
  [ValidateSet("off","on")]
  [string]$YYScoreMode = "off",
  [switch]$Resume,
  [switch]$Force,
  [switch]$AllowConcurrentHeavyJob
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $PSScriptRoot
$RFile = Join-Path $ProjectDir "99_run_yu_full_reproduction.R"
$PythonFile = Join-Path $ProjectDir "python/04_full_reproduction.py"
$ConfigFile = Join-Path $ProjectDir "config/full_reproduction_defaults.json"
if (-not $AnalysisRoot) { $AnalysisRoot = Join-Path $Dir0 "analysis" }
$AnalysisDir = Join-Path $AnalysisRoot $AnalysisProject
$LogDir = Join-Path $AnalysisDir "00_logs"
if ($Mode -ne "monitor") { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
if (-not $OlinkProcessingStartDateFile) {
  $OlinkProcessingStartDateFile = Join-Path $ProjectDir "references/raw/olink_processing_start_date.dat"
}
if (-not $MrOutcomeLookupDir) {
  $MrOutcomeLookupDir = Join-Path $AnalysisDir "11_mr/outcome_lookup"
}

$Rscript = @(
  "C:/Program Files/R/R-4.3.2/bin/x64/Rscript.exe",
  "C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
$PythonCandidates = @(
  "C:/Users/Dr.Liuyi/anaconda3/envs/yu_proteomic_repo_py39/python.exe",
  "C:/Users/Dr.Liuyi/anaconda3/python.exe"
)
if ($PythonExe) { $PythonCandidates = @($PythonExe) + $PythonCandidates }
$Python = $PythonCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Rscript) { throw "Rscript not found." }
$SystemsModes = @("systems_prepare","systems_enrichment","systems_tf","systems_ppi","systems_figures","figure6_systems")
if ($Mode -in $SystemsModes) {
  $SystemsInstaller = Join-Path $ProjectDir "tools/install_yu_systems_packages.R"
  & $Rscript --vanilla $SystemsInstaller
  if ($LASTEXITCODE -ne 0) { throw "Figure 6 systems package check failed." }
}
$NeedsPython = $Mode -in @("select", "train", "all", "all_fast")
if ($NeedsPython -and -not $Python) {
  throw "Python with lightgbm and scikit-learn not found. R-only modes remain available."
}

if ($PredictionPanelMode -eq "custom") {
  if (-not $CustomProteinPanelFile -and -not $CustomProteins) {
    throw "PredictionPanelMode=custom requires -CustomProteinPanelFile and/or -CustomProteins."
  }
  if ($CustomProteinPanelFile -and -not (Test-Path $CustomProteinPanelFile -PathType Leaf)) {
    throw "Custom protein panel file not found: $CustomProteinPanelFile"
  }
} elseif ($CustomProteinPanelFile -or $CustomProteins) {
  throw "CustomProteinPanelFile/CustomProteins require PredictionPanelMode=custom."
}

function Invoke-RStage([string]$Stage, [string[]]$ExtraArgs = @()) {
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $log = Join-Path $LogDir ("{0}_{1}.log" -f $Stage, $stamp)
  $argsList = @(
    "--vanilla", $RFile, "--mode=$Stage", "--dir0=$Dir0", "--analysis_root=$AnalysisRoot",
    "--analysis_project=$AnalysisProject", "--raw_protein_file=$RawProteinFile",
    "--cmr_feature_file=$CmrFeatureFile", "--cmr_metric_subset=$CmrMetricSubset",
    "--phenotype_rds=$PhenotypeRds", "--raw_phenotype_file=$RawPhenotypeFile",
    "--panel_mapping_file=$PanelMappingFile",
    "--olink_processing_start_date_file=$OlinkProcessingStartDateFile",
    "--endpoint_subset=$EndpointSubset", "--workers=$Workers", "--bootstrap_n=$BootstrapN",
    "--yys_mode=$YYScoreMode", "--prediction_panel_mode=$PredictionPanelMode",
    "--figure4_extra_projects=$Figure4ExtraProject",
    "--figure4_extra_outcomes=$Figure4ExtraOutcome",
    "--figure4_extra_labels=$Figure4ExtraLabel",
    "--pqtl_root=$PqtlRoot", "--mr_outcome_lookup_dir=$MrOutcomeLookupDir",
    "--cmest_shard_index=$CmestShardIndex", "--cmest_shard_count=$CmestShardCount",
    "--cmest_pilot_nboot=$CmestPilotBoot",
    "--string_required_score=$StringRequiredScore", "--systems_top_n_per_outcome=$SystemsTopN",
    "--systems_max_tf=$SystemsMaxTf",
    "--systems_enrichment_fdr=$SystemsFdr"
  )
  $argsList += $ExtraArgs
  if ($Resume) { $argsList += "--resume=true" }
  if ($Force) { $argsList += "--force=true" }
  Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | R stage=$Stage | log=$log"
  $old = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  & $Rscript @argsList 2>&1 | Tee-Object -FilePath $log
  $code = $LASTEXITCODE
  $ErrorActionPreference = $old
  if ($code -ne 0) { throw "R stage $Stage failed with exit code $code. See $log" }
}

function Invoke-PythonStage([string]$Stage) {
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $log = Join-Path $LogDir ("{0}_{1}.log" -f $Stage, $stamp)
  $argsList = @(
    $PythonFile, "--mode", $Stage, "--project-dir", $ProjectDir,
    "--analysis-dir", $AnalysisDir, "--raw-protein-file", $RawProteinFile,
    "--panel-mapping-file", $PanelMappingFile,
    "--config", $ConfigFile, "--endpoint-subset", $EndpointSubset,
    "--workers", $Workers, "--model-jobs", $ModelJobs,
    "--yys-mode", $YYScoreMode,
    "--prediction-panel-mode", $PredictionPanelMode
  )
  if ($CustomProteinPanelFile) { $argsList += @("--custom-protein-panel-file", $CustomProteinPanelFile) }
  if ($CustomProteins) { $argsList += @("--custom-proteins", $CustomProteins) }
  if ($Resume) { $argsList += "--resume" }
  Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Python stage=$Stage | log=$log"
  $old = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  & $Python @argsList 2>&1 | Tee-Object -FilePath $log
  $code = $LASTEXITCODE
  $ErrorActionPreference = $old
  if ($code -ne 0) { throw "Python stage $Stage failed with exit code $code. See $log" }
}

function Test-PythonEnvironment {
  if (-not $Python) { throw "Python with lightgbm, scikit-learn, pandas and numpy is required for the full workflow." }
  # dict() avoids Windows command-line quote stripping around JSON keys.
  $code = "import json,sys,lightgbm,sklearn,pandas,numpy; print(json.dumps(dict(status=chr(80)+chr(65)+chr(83)+chr(83),python='.'.join(map(str,sys.version_info[:3])),lightgbm=lightgbm.__version__,sklearn=sklearn.__version__,pandas=pandas.__version__,numpy=numpy.__version__)))"
  $json = & $Python -c $code
  if ($LASTEXITCODE -ne 0) { throw "Python package preflight failed." }
  $environment = $json | ConvertFrom-Json
  $pythonMajorMinor = (($environment.python -split '\.')[0..1] -join '.')
  if ($pythonMajorMinor -ne "3.9" -or $environment.lightgbm -ne "3.3.2") {
    throw "Formal reproduction requires Python 3.9 and lightgbm 3.3.2; found Python $($environment.python), lightgbm $($environment.lightgbm). Run tools/setup_yu_reproduction_python_windows.ps1 first."
  }
  $json | Set-Content -Encoding UTF8 (Join-Path $AnalysisDir "02_preflight/python_environment.json")
  Write-Host "Python environment: $json"
}

function Write-HardwareManifest {
  $cpu = Get-CimInstance Win32_Processor
  $os = Get-CimInstance Win32_OperatingSystem
  $hardware = [pscustomobject]@{
    timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    physical_cores = ($cpu | Measure-Object NumberOfCores -Sum).Sum
    logical_processors = ($cpu | Measure-Object NumberOfLogicalProcessors -Sum).Sum
    total_memory_gb = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    free_memory_gb = [Math]::Round($os.FreePhysicalMemory / 1MB, 1)
    workers = $Workers
    cox_jobs = $CoxJobs
    cmr_jobs = $CmrJobs
    model_jobs = $ModelJobs
    cmest_jobs = $CmestJobs
    cmest_pilot_bootstrap = $CmestPilotBoot
    yys_score_mode = $YYScoreMode
    endpoint_subset = $EndpointSubset
    prediction_panel_mode = $PredictionPanelMode
    custom_protein_panel_file = $CustomProteinPanelFile
    custom_proteins_inline = $CustomProteins
    python_executable = $Python
  }
  $hardware | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $LogDir "hardware_manifest.json")
}

function Assert-ComputeAvailable {
  if ($AllowConcurrentHeavyJob) { return }
  $other = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -in @("Rscript.exe", "python.exe") -and
    $_.CommandLine -and
    $_.CommandLine -notmatch [regex]::Escape($ProjectDir)
  })
  if ($other.Count -gt 0) {
    $details = ($other | ForEach-Object { "PID=$($_.ProcessId) $($_.CommandLine)" }) -join "`n"
    throw "Unrelated R/Python jobs are active. To keep both analyses valid and fast, wait for them to finish; no process was stopped.`n$details"
  }
}

function Get-RequestedEndpoints {
  $all = Import-Csv (Join-Path $ProjectDir "config/outcomes.csv")
  if ($EndpointSubset.Trim().ToLowerInvariant() -eq "all") { return @($all.outcome_id) }
  $requested = @($EndpointSubset.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $unknown = @($requested | Where-Object { $_ -notin $all.outcome_id })
  if ($unknown.Count -gt 0) { throw "Unknown endpoint IDs: $($unknown -join ', ')" }
  return $requested
}

function Invoke-CoxParallel {
  if ($CoxJobs -lt 1) { throw "CoxJobs must be >= 1." }
  Invoke-RStage "cox_prepare"
  $endpoints = @(Get-RequestedEndpoints)
  $jobs = [Math]::Min($CoxJobs, $endpoints.Count)
  $shardWorkers = [Math]::Max(1, [Math]::Floor($Workers / $jobs))
  Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Cox parallel endpoints=$($endpoints.Count) concurrent=$jobs fread_threads_per_shard=$shardWorkers"
  $queue = [System.Collections.Generic.Queue[string]]::new()
  foreach ($endpoint in $endpoints) { $queue.Enqueue($endpoint) }
  $running = @()
  $failures = @()

  while ($queue.Count -gt 0 -or $running.Count -gt 0) {
    while ($queue.Count -gt 0 -and $running.Count -lt $jobs) {
      $endpoint = $queue.Dequeue()
      $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
      $stdout = Join-Path $LogDir ("cox_{0}_{1}.out.log" -f $endpoint, $stamp)
      $stderr = Join-Path $LogDir ("cox_{0}_{1}.err.log" -f $endpoint, $stamp)
      $argsList = @(
        "--vanilla", $RFile, "--mode=cox_shard", "--dir0=$Dir0", "--analysis_root=$AnalysisRoot",
        "--analysis_project=$AnalysisProject", "--raw_protein_file=$RawProteinFile",
        "--phenotype_rds=$PhenotypeRds", "--raw_phenotype_file=$RawPhenotypeFile",
        "--panel_mapping_file=$PanelMappingFile",
        "--olink_processing_start_date_file=$OlinkProcessingStartDateFile",
        "--endpoint_subset=$endpoint", "--workers=$shardWorkers", "--bootstrap_n=$BootstrapN",
        "--yys_mode=$YYScoreMode", "--prediction_panel_mode=$PredictionPanelMode"
      )
      if ($Resume) { $argsList += "--resume=true" }
      if ($Force) { $argsList += "--force=true" }
      $process = Start-Process -FilePath $Rscript -ArgumentList $argsList -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
      $safeEndpoint = $endpoint -replace '[^A-Za-z0-9]+', '_'
      $doneMarker = Join-Path $LogDir ("cox_shard_{0}.done.json" -f $safeEndpoint)
      $expectedArtifacts = @(
        (Join-Path $AnalysisDir ("05_cox/full_incident_{0}_cox.csv.gz" -f $endpoint)),
        (Join-Path $AnalysisDir ("05_cox/full_incident_{0}_cox.contract.json" -f $endpoint)),
        (Join-Path $AnalysisDir ("05_cox/derivation_{0}_cox.csv.gz" -f $endpoint)),
        (Join-Path $AnalysisDir ("05_cox/derivation_{0}_cox.contract.json" -f $endpoint))
      )
      $running += [pscustomobject]@{
        Endpoint=$endpoint; Process=$process; Stdout=$stdout; Stderr=$stderr;
        DoneMarker=$doneMarker; ExpectedArtifacts=$expectedArtifacts; Started=Get-Date
      }
      Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | START Cox endpoint=$endpoint PID=$($process.Id)"
    }
    Start-Sleep -Seconds 2
    $next = @()
    foreach ($item in $running) {
      $item.Process.Refresh()
      if ($item.Process.HasExited) {
        # WaitForExit finalizes redirected streams and populates ExitCode reliably.
        $item.Process.WaitForExit()
        $exitCode = [int]$item.Process.ExitCode
        $elapsed = [Math]::Round(((Get-Date) - $item.Started).TotalMinutes, 1)
        $doneStatus = $null
        if (Test-Path $item.DoneMarker) {
          try { $doneStatus = (Get-Content $item.DoneMarker -Raw | ConvertFrom-Json).status } catch { $doneStatus = "INVALID" }
        }
        $missingArtifacts = @($item.ExpectedArtifacts | Where-Object { -not (Test-Path $_) })
        if ($exitCode -ne 0 -or $doneStatus -ne "PASS" -or $missingArtifacts.Count -gt 0) {
          $failures += $item
          Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | ERROR Cox endpoint=$($item.Endpoint) exit=$exitCode done_status=$doneStatus missing_artifacts=$($missingArtifacts.Count) stderr=$($item.Stderr)"
        } else {
          Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | DONE Cox endpoint=$($item.Endpoint) exit=$exitCode minutes=$elapsed"
        }
      } else {
        $next += $item
      }
    }
    $running = $next
  }
  if ($failures.Count -gt 0) {
    throw "Cox shards failed: $($failures.Endpoint -join ', '). Existing successful shards are retained for -Resume."
  }
  Invoke-RStage "cox_merge"
}

function Get-RequestedCmrMetrics {
  $all = Import-Csv (Join-Path $ProjectDir "config/cmr_metrics.csv")
  if ($CmrMetricSubset.Trim().ToLowerInvariant() -eq "all") { return @($all.metric_id) }
  $requested = @($CmrMetricSubset.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $unknown = @($requested | Where-Object { $_ -notin $all.metric_id })
  if ($unknown.Count -gt 0) { throw "Unknown CMR metric IDs: $($unknown -join ', ')" }
  return $requested
}

function Invoke-CmrParallel {
  if ($CmrJobs -lt 1) { throw "CmrJobs must be >= 1." }
  Invoke-RStage "cmr_prepare"
  $metrics = @(Get-RequestedCmrMetrics)
  $jobs = [Math]::Min($CmrJobs, $metrics.Count)
  $shardWorkers = [Math]::Max(1, [Math]::Floor($Workers / $jobs))
  Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | CMR parallel metrics=$($metrics.Count) concurrent=$jobs threads_per_shard=$shardWorkers"
  $queue = [System.Collections.Generic.Queue[string]]::new()
  foreach ($metric in $metrics) { $queue.Enqueue($metric) }
  $running = @()
  $failures = @()
  while ($queue.Count -gt 0 -or $running.Count -gt 0) {
    while ($queue.Count -gt 0 -and $running.Count -lt $jobs) {
      $metric = $queue.Dequeue()
      $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
      $stdout = Join-Path $LogDir ("cmr_{0}_{1}.out.log" -f $metric, $stamp)
      $stderr = Join-Path $LogDir ("cmr_{0}_{1}.err.log" -f $metric, $stamp)
      $argsList = @(
        "--vanilla", $RFile, "--mode=cmr_shard", "--dir0=$Dir0", "--analysis_root=$AnalysisRoot",
        "--analysis_project=$AnalysisProject", "--raw_protein_file=$RawProteinFile",
        "--cmr_feature_file=$CmrFeatureFile", "--cmr_metric_subset=$metric",
        "--phenotype_rds=$PhenotypeRds", "--raw_phenotype_file=$RawPhenotypeFile",
        "--panel_mapping_file=$PanelMappingFile",
        "--olink_processing_start_date_file=$OlinkProcessingStartDateFile",
        "--endpoint_subset=$EndpointSubset", "--workers=$shardWorkers", "--bootstrap_n=$BootstrapN",
        "--yys_mode=$YYScoreMode", "--prediction_panel_mode=$PredictionPanelMode"
      )
      if ($Resume) { $argsList += "--resume=true" }
      if ($Force) { $argsList += "--force=true" }
      $process = Start-Process -FilePath $Rscript -ArgumentList $argsList -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
      $running += [pscustomobject]@{
        Metric=$metric; Process=$process; Stdout=$stdout; Stderr=$stderr; Started=Get-Date;
        Result=(Join-Path $AnalysisDir ("07_cmr/cmr_{0}.csv.gz" -f $metric));
        Contract=(Join-Path $AnalysisDir ("07_cmr/cmr_{0}.contract.json" -f $metric))
      }
      Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | START CMR metric=$metric PID=$($process.Id)"
    }
    Start-Sleep -Seconds 2
    $next = @()
    foreach ($item in $running) {
      $item.Process.Refresh()
      if ($item.Process.HasExited) {
        $item.Process.WaitForExit()
        $exitCode = [int]$item.Process.ExitCode
        $elapsed = [Math]::Round(((Get-Date) - $item.Started).TotalMinutes, 1)
        if ($exitCode -ne 0 -or -not (Test-Path $item.Result) -or -not (Test-Path $item.Contract)) {
          $failures += $item
          Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | ERROR CMR metric=$($item.Metric) exit=$exitCode stderr=$($item.Stderr)"
        } else {
          Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | DONE CMR metric=$($item.Metric) minutes=$elapsed"
        }
      } else { $next += $item }
    }
    $running = $next
  }
  if ($failures.Count -gt 0) {
    throw "CMR shards failed: $($failures.Metric -join ', '). Successful shards are retained for -Resume."
  }
  if ($CmrMetricSubset.Trim().ToLowerInvariant() -eq "all") { Invoke-RStage "cmr_merge" }
}

function Invoke-CmestParallel {
  if ($CmestJobs -lt 1) { throw "CmestJobs must be >= 1." }
  $candidateFile = Join-Path $AnalysisDir "12_mediation/mediation_candidate_triangles.csv"
  $pilotSummary = Join-Path $AnalysisDir "12_mediation/mediation_cmest_pilot_summary.json"
  if (-not (Test-Path $candidateFile)) {
    throw "Run -Mode mediation_run first to freeze mediation_candidate_triangles.csv."
  }
  if (-not (Test-Path $pilotSummary)) {
    throw "Run -Mode mediation_cmest_pilot first; full CMAverse execution requires a measured pilot."
  }
  $pilot = Get-Content $pilotSummary -Raw | ConvertFrom-Json
  if ($pilot.status -ne "PASS") { throw "CMAverse pilot is not PASS." }

  $shardCount = $CmestJobs
  Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | CMAverse parallel shards=$shardCount bootstrap_per_path=$BootstrapN"
  Write-Host "Pilot: $($pilot.path); seconds=$([Math]::Round([double]$pilot.elapsed_seconds,1)); projected_hours_at_8_jobs=$([Math]::Round([double]$pilot.projected_hours_at_8_jobs,1))"
  $running = @()
  $failures = @()
  for ($index = 1; $index -le $shardCount; $index++) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $stdout = Join-Path $LogDir ("cmest_{0:D3}_of_{1:D3}_{2}.out.log" -f $index, $shardCount, $stamp)
    $stderr = Join-Path $LogDir ("cmest_{0:D3}_of_{1:D3}_{2}.err.log" -f $index, $shardCount, $stamp)
    $argsList = @(
      "--vanilla", $RFile, "--mode=mediation_cmest_shard", "--dir0=$Dir0", "--analysis_root=$AnalysisRoot",
      "--analysis_project=$AnalysisProject", "--raw_protein_file=$RawProteinFile",
      "--cmr_feature_file=$CmrFeatureFile", "--cmr_metric_subset=$CmrMetricSubset",
      "--phenotype_rds=$PhenotypeRds", "--raw_phenotype_file=$RawPhenotypeFile",
      "--panel_mapping_file=$PanelMappingFile",
      "--olink_processing_start_date_file=$OlinkProcessingStartDateFile",
      "--endpoint_subset=$EndpointSubset", "--workers=1", "--bootstrap_n=$BootstrapN",
      "--yys_mode=$YYScoreMode", "--prediction_panel_mode=$PredictionPanelMode",
      "--pqtl_root=$PqtlRoot", "--mr_outcome_lookup_dir=$MrOutcomeLookupDir",
      "--cmest_shard_index=$index", "--cmest_shard_count=$shardCount",
      "--cmest_pilot_nboot=$CmestPilotBoot"
    )
    if ($Resume) { $argsList += "--resume=true" }
    if ($Force) { $argsList += "--force=true" }
    $process = Start-Process -FilePath $Rscript -ArgumentList $argsList -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
    $running += [pscustomobject]@{
      Index=$index; Process=$process; Stdout=$stdout; Stderr=$stderr; Started=Get-Date;
      Result=(Join-Path $AnalysisDir ("12_mediation/cmest_shards/cmest_shard_{0:D3}_of_{1:D3}.csv" -f $index, $shardCount));
      Contract=(Join-Path $AnalysisDir ("12_mediation/cmest_shards/cmest_shard_{0:D3}_of_{1:D3}.contract.json" -f $index, $shardCount))
    }
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | START CMAverse shard=$index/$shardCount PID=$($process.Id)"
  }

  while ($running.Count -gt 0) {
    Start-Sleep -Seconds 5
    $next = @()
    foreach ($item in $running) {
      $item.Process.Refresh()
      if ($item.Process.HasExited) {
        $item.Process.WaitForExit()
        $exitCode = [int]$item.Process.ExitCode
        $elapsed = [Math]::Round(((Get-Date) - $item.Started).TotalHours, 2)
        if ($exitCode -ne 0 -or -not (Test-Path $item.Result) -or -not (Test-Path $item.Contract)) {
          $failures += $item
          Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | ERROR CMAverse shard=$($item.Index)/$shardCount exit=$exitCode stderr=$($item.Stderr)"
        } else {
          Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | DONE CMAverse shard=$($item.Index)/$shardCount hours=$elapsed"
        }
      } else { $next += $item }
    }
    $running = $next
  }
  if ($failures.Count -gt 0) {
    throw "CMAverse shards failed: $($failures.Index -join ', '). Completed shards are retained for -Resume."
  }
  Invoke-RStage "mediation_cmest_merge" @("--cmest_shard_count=$shardCount", "--cmest_shard_index=1")
}

function Show-Monitor {
  Write-Host "Analysis: $AnalysisDir"
  Write-Host "YYScoreMode: $YYScoreMode"
  Write-Host "Active project processes:"
  Get-CimInstance Win32_Process |
    Where-Object { $_.Name -in @("Rscript.exe", "python.exe") -and $_.CommandLine -match [regex]::Escape($ProjectDir) } |
    Select-Object ProcessId, Name, CreationDate, CommandLine |
    Format-Table -AutoSize
  Write-Host "Stage markers:"
  Get-ChildItem $LogDir -Filter "*.done.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime |
    Select-Object Name, Length, LastWriteTime |
    Format-Table -AutoSize
  $runLog = Join-Path $LogDir "run.log"
  if (Test-Path $runLog) {
    Write-Host "Last 40 run.log lines:"
    Get-Content $runLog -Tail 40
  }
}

if ($Mode -ne "monitor") { Write-HardwareManifest }
if ($Mode -eq "help") { Invoke-RStage "help"; exit 0 }
switch ($Mode) {
  "sources"   { Invoke-RStage "sources" }
  "preflight" { Invoke-RStage "preflight"; Test-PythonEnvironment }
  "cohort"    { Invoke-RStage "cohort" }
  "cox_prepare" { Invoke-RStage "cox_prepare" }
  "cox_shard"  { Invoke-RStage "cox_shard" }
  "cox_merge"  { Invoke-RStage "cox_merge" }
  "cox"       { Invoke-RStage "cox" }
  "cox_parallel" { Assert-ComputeAvailable; Invoke-CoxParallel }
  "cmr_prepare" { Invoke-RStage "cmr_prepare" }
  "cmr_shard"   { Invoke-RStage "cmr_shard" }
  "cmr_merge"   { Invoke-RStage "cmr_merge" }
  "cmr"         { Assert-ComputeAvailable; Invoke-RStage "cmr" }
  "cmr_parallel" { Assert-ComputeAvailable; Invoke-CmrParallel }
  "mr_prepare" { Invoke-RStage "mr_prepare" }
  "mr_run" { Assert-ComputeAvailable; Invoke-RStage "mr_run" }
  "mediation_prepare" { Assert-ComputeAvailable; Invoke-RStage "mediation_prepare" }
  "mediation_run" { Assert-ComputeAvailable; Invoke-RStage "mediation_run" }
  "mediation_cmest_pilot" { Assert-ComputeAvailable; Invoke-RStage "mediation_cmest_pilot" }
  "mediation_cmest_shard" { Assert-ComputeAvailable; Invoke-RStage "mediation_cmest_shard" }
  "mediation_cmest_merge" { Invoke-RStage "mediation_cmest_merge" }
  "mediation_cmest_parallel" { Assert-ComputeAvailable; Invoke-CmestParallel }
  "systems_prepare" { Invoke-RStage "systems_prepare" }
  "systems_enrichment" { Invoke-RStage "systems_enrichment" }
  "systems_tf" { Invoke-RStage "systems_tf" }
  "systems_ppi" { Invoke-RStage "systems_ppi" }
  "systems_figures" { Invoke-RStage "systems_figures" }
  "figure6_systems" {
    Invoke-RStage "systems_prepare"
    Invoke-RStage "systems_enrichment"
    Invoke-RStage "systems_tf"
    Invoke-RStage "systems_ppi"
    Invoke-RStage "systems_figures"
  }
  "figure5_local" {
    Invoke-RStage "mr_prepare"
    Invoke-RStage "mr_run"
    Invoke-RStage "mediation_prepare"
    Invoke-RStage "mediation_run"
    Invoke-RStage "figures"
  }
  "select"    { Assert-ComputeAvailable; Invoke-PythonStage "select" }
  "yys"       {
    if ($YYScoreMode -ne "on") { throw "Mode=yys requires -YYScoreMode on." }
    Invoke-RStage "yys"
  }
  "train"     { Assert-ComputeAvailable; Invoke-PythonStage "train" }
  "evaluate"  { Invoke-RStage "evaluate" }
  "figures"   { Invoke-RStage "figures" }
  "report"    { Invoke-RStage "report" }
  "monitor"   { Show-Monitor }
  "all" {
    Assert-ComputeAvailable
    Invoke-RStage "sources"
    Invoke-RStage "preflight"
    Test-PythonEnvironment
    Invoke-RStage "cohort"
    Invoke-RStage "cox"
    Invoke-RStage "cmr"
    Invoke-PythonStage "select"
    if ($YYScoreMode -eq "on") { Invoke-RStage "yys" }
    Invoke-PythonStage "train"
    Invoke-RStage "evaluate"
    Invoke-RStage "figures"
    Invoke-RStage "report"
  }
  "all_fast" {
    Assert-ComputeAvailable
    Invoke-RStage "sources"
    Invoke-RStage "preflight"
    Test-PythonEnvironment
    Invoke-RStage "cohort"
    Invoke-CoxParallel
    Invoke-CmrParallel
    Invoke-PythonStage "select"
    if ($YYScoreMode -eq "on") { Invoke-RStage "yys" }
    Invoke-PythonStage "train"
    Invoke-RStage "evaluate"
    Invoke-RStage "figures"
    Invoke-RStage "report"
  }
}
Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | COMPLETE mode=$Mode | yys_score_mode=$YYScoreMode | analysis=$AnalysisDir"
