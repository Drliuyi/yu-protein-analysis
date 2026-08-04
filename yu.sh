#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
entry_ps1="${project_dir}/yu.ps1"

show_help() {
  cat <<'EOF'
Yu Protein Analysis shell entry

Usage:
  ./yu.sh install
  ./yu.sh doctor
  ./yu.sh setup
  ./yu.sh 1-4 --resume
  ./yu.sh finalize --resume
  ./yu.sh --step figures --force
  ./yu.sh --step 4 --disease cad --workers 16 --resume

Common options:
  --step VALUE                 Step number/list/range or named mode.
  --disease VALUE              all, cad, heart_failure, or a comma list.
  --protein-panel VALUE        local_reselected, published_257, or custom.
  --model-protein-file PATH    Custom protein panel file.
  --analysis-project NAME      Output project folder name.
  --workers N                  Total workers.
  --cox-jobs N                 Concurrent Cox shards.
  --model-jobs N               Concurrent model jobs.
  --resume                     Reuse completed stages and shards.
  --force                      Rebuild the selected stage.
  --confirm-heavy              Confirm long-running steps 8 or 9.
  --plan-only                  Print the plan without computation.

Path options:
  --dir0 PATH                  Logical D-drive root; default D:/.
  --phe-dir PATH               Phenotype root.
  --analysis-root PATH         Analysis output root.
  --raw-protein-file PATH      Unimputed protein table.
  --phenotype-rds PATH         Phenotype RDS.
  --panel-mapping-file PATH    Olink mapping table.
  --supplement-workbook-file PATH
                                Official Tables S1-S26 workbook.
  --supplement-methods-file PATH
                                Official supplementary methods PDF.
  --olink-processing-start-date-file PATH
                                UKB Olink processing-date resource.
  --windows-nas-root PATH      Windows genotype root.
  --rscript-exe PATH           Rscript override.
  --python-exe PATH            Frozen Python 3.9 override.
  --conda-exe PATH             Conda override used by install.
  --path-prompt-mode MODE      Auto, Dialog, Console, or Off.
  --reset-paths                Rebuild the saved local path profile.

This is a thin WSL/Git Bash wrapper around yu.ps1. Path overrides passed to
Windows PowerShell should use Windows-style paths such as D:/data/ukb/phe.
Run './yu.sh help' for the complete step and disease catalogue.
EOF
}

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" ]]; then
    printf 'ERROR: %s requires a value.\n' "$1" >&2
    exit 2
  fi
}

ps_args=()
step_seen=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    --step=*)
      ps_args+=("-Step" "${1#*=}")
      step_seen=1
      shift
      ;;
    --step|-Step)
      require_value "$@"
      ps_args+=("-Step" "$2")
      step_seen=1
      shift 2
      ;;
    --dir0) require_value "$@"; ps_args+=("-Dir0" "$2"); shift 2 ;;
    --analysis-root) require_value "$@"; ps_args+=("-AnalysisRoot" "$2"); shift 2 ;;
    --analysis-project) require_value "$@"; ps_args+=("-AnalysisProject" "$2"); shift 2 ;;
    --project-dir) require_value "$@"; ps_args+=("-ProjectDir" "$2"); shift 2 ;;
    --script-root) require_value "$@"; ps_args+=("-ScriptRoot" "$2"); shift 2 ;;
    --phe-dir) require_value "$@"; ps_args+=("-PheDir" "$2"); shift 2 ;;
    --raw-protein-file) require_value "$@"; ps_args+=("-RawProteinFile" "$2"); shift 2 ;;
    --phenotype-rds) require_value "$@"; ps_args+=("-PhenotypeRds" "$2"); shift 2 ;;
    --raw-phenotype-file) require_value "$@"; ps_args+=("-RawPhenotypeFile" "$2"); shift 2 ;;
    --panel-mapping-file) require_value "$@"; ps_args+=("-PanelMappingFile" "$2"); shift 2 ;;
    --supplement-workbook-file) require_value "$@"; ps_args+=("-SupplementWorkbookFile" "$2"); shift 2 ;;
    --supplement-methods-file) require_value "$@"; ps_args+=("-SupplementMethodsFile" "$2"); shift 2 ;;
    --olink-processing-start-date-file) require_value "$@"; ps_args+=("-OlinkProcessingStartDateFile" "$2"); shift 2 ;;
    --cmr-feature-file) require_value "$@"; ps_args+=("-CmrFeatureFile" "$2"); shift 2 ;;
    --pqtl-root) require_value "$@"; ps_args+=("-PqtlRoot" "$2"); shift 2 ;;
    --mr-outcome-lookup-dir) require_value "$@"; ps_args+=("-MrOutcomeLookupDir" "$2"); shift 2 ;;
    --disease) require_value "$@"; ps_args+=("-Disease" "$2"); shift 2 ;;
    --workers) require_value "$@"; ps_args+=("-Workers" "$2"); shift 2 ;;
    --cox-jobs) require_value "$@"; ps_args+=("-CoxJobs" "$2"); shift 2 ;;
    --cmr-jobs) require_value "$@"; ps_args+=("-CmrJobs" "$2"); shift 2 ;;
    --model-jobs) require_value "$@"; ps_args+=("-ModelJobs" "$2"); shift 2 ;;
    --bootstrap-n) require_value "$@"; ps_args+=("-BootstrapN" "$2"); shift 2 ;;
    --cmest-jobs) require_value "$@"; ps_args+=("-CmestJobs" "$2"); shift 2 ;;
    --cmest-pilot-boot) require_value "$@"; ps_args+=("-CmestPilotBoot" "$2"); shift 2 ;;
    --score-jobs) require_value "$@"; ps_args+=("-ScoreJobs" "$2"); shift 2 ;;
    --association-jobs) require_value "$@"; ps_args+=("-AssociationJobs" "$2"); shift 2 ;;
    --memory-mb) require_value "$@"; ps_args+=("-MemoryMb" "$2"); shift 2 ;;
    --genotype-mode) require_value "$@"; ps_args+=("-GenotypeMode" "$2"); shift 2 ;;
    --windows-nas-root) require_value "$@"; ps_args+=("-WindowsNasRoot" "$2"); shift 2 ;;
    --rscript-exe) require_value "$@"; ps_args+=("-RscriptExe" "$2"); shift 2 ;;
    --python-exe) require_value "$@"; ps_args+=("-PythonExe" "$2"); shift 2 ;;
    --conda-exe) require_value "$@"; ps_args+=("-CondaExe" "$2"); shift 2 ;;
    --nas-mount-root) require_value "$@"; ps_args+=("-NasMountRoot" "$2"); shift 2 ;;
    --protein-panel) require_value "$@"; ps_args+=("-ProteinPanel" "$2"); shift 2 ;;
    --model-protein-file) require_value "$@"; ps_args+=("-ModelProteinFile" "$2"); shift 2 ;;
    --model-proteins) require_value "$@"; ps_args+=("-ModelProteins" "$2"); shift 2 ;;
    --figure4-extra-project) require_value "$@"; ps_args+=("-Figure4ExtraProject" "$2"); shift 2 ;;
    --figure4-extra-outcome) require_value "$@"; ps_args+=("-Figure4ExtraOutcome" "$2"); shift 2 ;;
    --figure4-extra-label) require_value "$@"; ps_args+=("-Figure4ExtraLabel" "$2"); shift 2 ;;
    --string-required-score) require_value "$@"; ps_args+=("-StringRequiredScore" "$2"); shift 2 ;;
    --systems-top-n) require_value "$@"; ps_args+=("-SystemsTopN" "$2"); shift 2 ;;
    --systems-max-tf) require_value "$@"; ps_args+=("-SystemsMaxTf" "$2"); shift 2 ;;
    --systems-fdr) require_value "$@"; ps_args+=("-SystemsFdr" "$2"); shift 2 ;;
    --path-prompt-mode) require_value "$@"; ps_args+=("-PathPromptMode" "$2"); shift 2 ;;
    --path-config) require_value "$@"; ps_args+=("-PathConfig" "$2"); shift 2 ;;
    --resume) ps_args+=("-Resume"); shift ;;
    --force) ps_args+=("-Force"); shift ;;
    --confirm-heavy) ps_args+=("-ConfirmHeavy"); shift ;;
    --plan-only) ps_args+=("-PlanOnly"); shift ;;
    --reset-paths) ps_args+=("-ResetPaths"); shift ;;
    --allow-concurrent-heavy-job) ps_args+=("-AllowConcurrentHeavyJob"); shift ;;
    --keep-streamed-genotype) ps_args+=("-KeepStreamedGenotype"); shift ;;
    --)
      shift
      ps_args+=("$@")
      break
      ;;
    -*)
      printf 'ERROR: unknown shell option: %s\n' "$1" >&2
      printf 'Run ./yu.sh --help for supported options.\n' >&2
      exit 2
      ;;
    *)
      if [[ ${step_seen} -eq 0 ]]; then
        ps_args+=("-Step" "$1")
        step_seen=1
        shift
      else
        printf 'ERROR: unexpected positional argument: %s\n' "$1" >&2
        exit 2
      fi
      ;;
  esac
done

if [[ ${step_seen} -eq 0 ]]; then
  ps_args+=("-Step" "help")
fi

if [[ ! -f "${entry_ps1}" ]]; then
  printf 'ERROR: PowerShell entry not found: %s\n' "${entry_ps1}" >&2
  exit 3
fi

if command -v powershell.exe >/dev/null 2>&1; then
  windows_entry="${entry_ps1}"
  if command -v wslpath >/dev/null 2>&1; then
    windows_entry="$(wslpath -w "${entry_ps1}")"
  elif command -v cygpath >/dev/null 2>&1; then
    windows_entry="$(cygpath -w "${entry_ps1}")"
  fi
  exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${windows_entry}" "${ps_args[@]}"
fi

if command -v pwsh >/dev/null 2>&1; then
  exec pwsh -NoProfile -File "${entry_ps1}" "${ps_args[@]}"
fi

if command -v powershell >/dev/null 2>&1; then
  exec powershell -NoProfile -File "${entry_ps1}" "${ps_args[@]}"
fi

printf '%s\n' \
  'ERROR: PowerShell was not found.' \
  'Run this wrapper in WinPC WSL/Git Bash, or install PowerShell 7 (pwsh).' >&2
exit 127
