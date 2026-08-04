#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/mnt/d/scripts/yy_cad_yu_yys}"
DIRECT_NAS_ROOT="${DIRECT_NAS_ROOT:-/mnt/z/projects/genotype_pc_nas/imputed_pgen_autosomes}"
WINDOWS_NAS_DRIVE="${WINDOWS_NAS_DRIVE:-Z:}"

if [[ "${DIRECT_NAS_ROOT}" =~ ^(/mnt/[^/]+) ]]; then
  mount_point="${BASH_REMATCH[1]}"
else
  echo "ERROR: DIRECT_NAS_ROOT must start with /mnt/<drive>: ${DIRECT_NAS_ROOT}" >&2
  exit 41
fi

mkdir -p "${mount_point}"
if ! mountpoint -q "${mount_point}"; then
  mount -t drvfs "${WINDOWS_NAS_DRIVE}" "${mount_point}"
fi

for chr in $(seq 1 22); do
  for ext in pgen pvar psam; do
    file="${DIRECT_NAS_ROOT}/chr${chr}/pgen/chr${chr}_imp.${ext}"
    [ -s "${file}" ] || {
      echo "ERROR: missing direct NAS genotype: ${file}" >&2
      exit 42
    }
  done
done

echo "Direct NAS QC PASS: 22 chromosomes x PGEN/PVAR/PSAM"
exec bash "${PROJECT_DIR}/f/wsl/13_score_prs_stream.sh"
