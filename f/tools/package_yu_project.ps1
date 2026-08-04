param(
  [string]$ProjectDir = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
  [string]$OutputDir = "",
  [string]$PackageName = ""
)

$ErrorActionPreference = "Stop"
if (-not $OutputDir) { $OutputDir = Join-Path $ProjectDir "dist" }
if (-not $PackageName) { $PackageName = "Yu_protein_analysis_code_$(Get-Date -Format 'yyyyMMdd')" }

$ProjectDir = (Resolve-Path $ProjectDir).Path
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path $OutputDir).Path
$stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("yu_package_" + [guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $stageRoot "yy_cad_yu_yys"
$zipFile = Join-Path $OutputDir ($PackageName + ".zip")
$hashFile = $zipFile + ".sha256"

New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null

function Test-PackageFile([string]$RelativePath) {
  $value = ($RelativePath -replace "\\", "/")
  if ($value -match "(^|/)__pycache__(/|$)") { return $false }
  if ($value -match "(^|/)(analysis|archive|backups|dist|legacy)(/|$)") { return $false }
  if ($value -match "(^|/)f/tools/bin(/|$)") { return $false }
  if ($value -match "(?i)\.pyc$") { return $false }
  if ($value -match "(?i)(^|/)Rplots\.pdf$") { return $false }
  if ($value -match "(?i)(^|/)\.DS_Store$") { return $false }
  return $true
}

try {
  $sourceFiles = @(Get-ChildItem $ProjectDir -Recurse -File | Where-Object {
    $relative = $_.FullName.Substring($ProjectDir.Length) -replace "^[\\/]+", ""
    Test-PackageFile $relative
  })

  foreach ($file in $sourceFiles) {
    $relative = $file.FullName.Substring($ProjectDir.Length) -replace "^[\\/]+", ""
    $destination = Join-Path $packageRoot $relative
    $parent = Split-Path -Parent $destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Copy-Item $file.FullName $destination -Force
  }

  $manifestRows = @(Get-ChildItem $packageRoot -Recurse -File | ForEach-Object {
    [pscustomobject]@{
      relative_path = (($_.FullName.Substring($packageRoot.Length) -replace "^[\\/]+", "") -replace "\\", "/")
      size_bytes = $_.Length
      sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
  } | Sort-Object relative_path)
  $manifestFile = Join-Path $packageRoot "FILE_MANIFEST_SHA256.csv"
  $manifestRows | Export-Csv $manifestFile -NoTypeInformation -Encoding UTF8

  if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
  if (Test-Path $hashFile) { Remove-Item $hashFile -Force }
  Compress-Archive -Path $packageRoot -DestinationPath $zipFile -CompressionLevel Optimal
  $zipHash = (Get-FileHash $zipFile -Algorithm SHA256).Hash.ToLowerInvariant()
  "$zipHash  $([System.IO.Path]::GetFileName($zipFile))" | Set-Content $hashFile -Encoding ASCII

  Write-Host "PACKAGE COMPLETE"
  Write-Host "  ZIP      : $zipFile"
  Write-Host "  SHA256   : $zipHash"
  Write-Host "  FILES    : $($manifestRows.Count + 1)"
  Write-Host "  SIZE MB  : $([math]::Round((Get-Item $zipFile).Length / 1MB, 2))"
} finally {
  if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }
}
