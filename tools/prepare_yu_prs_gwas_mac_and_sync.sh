#!/usr/bin/env bash
set -euo pipefail

# The Mac is the orchestration and writing host. Keep bulk PRS/GWAS staging on
# WinPC/WSL or Zspace so an accidental local run cannot fill the Mac disk.
if [[ "${ALLOW_MAC_BULK_PRS_STAGE:-0}" != "1" ]]; then
  printf '%s\n' \
    "REFUSED: bulk PRS/GWAS staging is disabled on the Mac by default." \
    "Run the preparation step on WinPC/WSL instead:" \
    "  /mnt/d/UKB_data/scripts/yy_cad_yu_yys/wsl/13_prepare_prs_gwas.sh" \
    "Emergency override only: ALLOW_MAC_BULK_PRS_STAGE=1"
  exit 64
fi

PROJECT_DIR="${PROJECT_DIR:-/Users/drlau/Documents/UKB_data/scripts/yy_cad_yu_yys}"
LOCAL_ANALYSIS_DIR="${LOCAL_ANALYSIS_DIR:-/Users/drlau/Documents/UKB_data/tmp/yu_proteomic_repo_v3_prs_mac}"
WINPC_ALIAS="${WINPC_ALIAS:-winpc}"
REMOTE_ANALYSIS_DIR="${REMOTE_ANALYSIS_DIR:-/d/UKB_data/analysis/yu_proteomic_repo_v3}"
REMOTE_SFTP_ANALYSIS_DIR="${REMOTE_SFTP_ANALYSIS_DIR:-/D:/UKB_data/analysis/yu_proteomic_repo_v3}"
MAX_P="${MAX_P:-0.0005}"

LOCAL_PRS_DIR="${LOCAL_ANALYSIS_DIR}/13_prs"
LOCAL_NORMALIZED_DIR="${LOCAL_PRS_DIR}/gwas_normalized"
REMOTE_PRS_DIR="${REMOTE_ANALYSIS_DIR}/13_prs"
REMOTE_SFTP_PRS_DIR="${REMOTE_SFTP_ANALYSIS_DIR}/13_prs"
LOG_DIR="${LOCAL_ANALYSIS_DIR}/00_logs"
STAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE="${LOG_DIR}/prepare_gwas_mac_${STAMP}.log"

mkdir -p "${LOCAL_NORMALIZED_DIR}" "${LOG_DIR}"

expected="$(($(wc -l < "${PROJECT_DIR}/config/prs_gwas_sources.tsv") - 1))"
shopt -s nullglob
existing_normalized=("${LOCAL_NORMALIZED_DIR}"/*.maxp_"${MAX_P}".tsv.gz)
ssh "${WINPC_ALIAS}" "mkdir -p '${REMOTE_PRS_DIR}/gwas_normalized'"
if [ "${#existing_normalized[@]}" -lt "${expected}" ]; then
  echo "[$(date '+%F %T')] Pulling existing small normalized files from WinPC." | tee -a "${LOG_FILE}"
  scp -rq "${WINPC_ALIAS}:${REMOTE_SFTP_PRS_DIR}/gwas_normalized/." "${LOCAL_NORMALIZED_DIR}/" 2>/dev/null || true
fi

echo "[$(date '+%F %T')] Downloading and filtering GWAS on Mac." | tee -a "${LOG_FILE}"
PROJECT_DIR="${PROJECT_DIR}" \
ANALYSIS_DIR="${LOCAL_ANALYSIS_DIR}" \
MAX_P="${MAX_P}" \
RESUME=1 \
bash "${PROJECT_DIR}/wsl/13_prepare_prs_gwas.sh" 2>&1 | tee -a "${LOG_FILE}"

normalized_files=("${LOCAL_NORMALIZED_DIR}"/*.maxp_"${MAX_P}".tsv.gz)
actual="${#normalized_files[@]}"
if [ "${actual}" -ne "${expected}" ]; then
  echo "ERROR: normalized GWAS count ${actual}/${expected}" | tee -a "${LOG_FILE}" >&2
  exit 21
fi

while IFS= read -r file; do
  gzip -t "${file}"
done < <(find "${LOCAL_NORMALIZED_DIR}" -type f -name '*.gz' | sort)

echo "[$(date '+%F %T')] Syncing normalized weights to WinPC (${actual}/${expected})." | tee -a "${LOG_FILE}"
bundle_name="gwas_normalized_${STAMP}.tar.gz"
bundle_file="${LOCAL_PRS_DIR}/${bundle_name}"
COPYFILE_DISABLE=1 tar -C "${LOCAL_NORMALIZED_DIR}" -czf "${bundle_file}" .
scp -q "${bundle_file}" "${WINPC_ALIAS}:${REMOTE_SFTP_PRS_DIR}/${bundle_name}"
ssh "${WINPC_ALIAS}" \
  "tar -xzf '${REMOTE_PRS_DIR}/${bundle_name}' -C '${REMOTE_PRS_DIR}/gwas_normalized' && find '${REMOTE_PRS_DIR}/gwas_normalized' -name '._*' -type f -delete"

scp -q "${LOCAL_PRS_DIR}/gwas_prepare_status.tsv" \
  "${WINPC_ALIAS}:${REMOTE_SFTP_PRS_DIR}/gwas_prepare_status_mac.tsv"
scp -q "${LOG_FILE}" "${WINPC_ALIAS}:${REMOTE_SFTP_ANALYSIS_DIR}/00_logs/"

remote_count="$(ssh "${WINPC_ALIAS}" "find '${REMOTE_PRS_DIR}/gwas_normalized' -maxdepth 1 -type f ! -name '._*' -name '*.maxp_${MAX_P}.tsv.gz' | wc -l")"
remote_count="$(printf '%s' "${remote_count}" | tr -d '[:space:]')"
if [ "${remote_count}" -ne "${expected}" ]; then
  echo "ERROR: WinPC normalized GWAS count ${remote_count}/${expected}" | tee -a "${LOG_FILE}" >&2
  exit 22
fi

echo "[$(date '+%F %T')] COMPLETE: ${remote_count}/${expected} normalized GWAS files are ready on WinPC." | tee -a "${LOG_FILE}"
