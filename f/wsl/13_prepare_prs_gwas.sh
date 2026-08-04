#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/mnt/d/scripts/yy_cad_yu_yys}"
ANALYSIS_DIR="${ANALYSIS_DIR:-/mnt/d/analysis/yu_proteomic_repo_v3}"
SOURCE_FILE="${SOURCE_FILE:-${PROJECT_DIR}/f/config/prs_gwas_sources.tsv}"
PRS_DIR="${PRS_DIR:-${ANALYSIS_DIR}/13_prs}"
RAW_DIR="${PRS_DIR}/gwas_raw"
NORMALIZED_DIR="${PRS_DIR}/gwas_normalized"
LOG_DIR="${ANALYSIS_DIR}/00_logs"
MAX_P="${MAX_P:-0.0005}"
RESUME="${RESUME:-1}"

mkdir -p "${RAW_DIR}" "${NORMALIZED_DIR}" "${LOG_DIR}"

for command_name in curl gzip awk sort; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "ERROR: required command is unavailable: ${command_name}" >&2
    exit 1
  }
done

if command -v sha256sum >/dev/null 2>&1; then
  checksum_file() { sha256sum "$1" | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  checksum_file() { shasum -a 256 "$1" | awk '{print $1}'; }
else
  echo "ERROR: neither sha256sum nor shasum is available" >&2
  exit 1
fi

timestamp_iso() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

if [ ! -s "${SOURCE_FILE}" ]; then
  echo "ERROR: PRS source manifest is missing: ${SOURCE_FILE}" >&2
  exit 1
fi

status_file="${PRS_DIR}/gwas_prepare_status.tsv"
if [ ! -f "${status_file}" ]; then
  printf 'outcome_id\tsource_id\tstatus\traw_file\tnormalized_file\tretained_variants\tsha256\tcompleted_at\n' > "${status_file}"
fi

normalize_finngen() {
  local input="$1"
  local output="$2"
  local body="${output}.body.tmp"
  gzip -dc "${input}" | awk -F '\t' -v OFS='\t' -v maxp="${MAX_P}" '
    NR == 1 {
      for (i = 1; i <= NF; i++) h[$i] = i
      required[1]="#chrom"; required[2]="pos"; required[3]="ref"; required[4]="alt"
      required[5]="rsids"; required[6]="pval"; required[7]="beta"
      for (i = 1; i <= 7; i++) if (!(required[i] in h)) {
        print "ERROR: missing FinnGen field " required[i] > "/dev/stderr"; exit 12
      }
      next
    }
    {
      chr=$(h["#chrom"]); pos=$(h["pos"]); ref=toupper($(h["ref"])); alt=toupper($(h["alt"]))
      id=$(h["rsids"]); p=$(h["pval"])+0; beta=$(h["beta"])+0
      split(id, ids, /[,;]/); id=ids[1]
      if (chr ~ /^[0-9]+$/ && chr >= 1 && chr <= 22 && id ~ /^rs[0-9]+$/ &&
          p > 0 && p <= maxp && ref ~ /^[ACGT]+$/ && alt ~ /^[ACGT]+$/) {
        print id, chr, pos, alt, ref, beta, p
      }
    }
  ' | LC_ALL=C sort -t $'\t' -k2,2n -k1,1 -k7,7g | awk -F '\t' -v OFS='\t' '
    $1 != previous { print; previous=$1 }
  ' > "${body}"
  { printf 'ID\tCHR\tPOS\tA1\tA2\tBETA\tP\n'; cat "${body}"; } | gzip -c > "${output}.tmp"
  rm -f "${body}"
  mv "${output}.tmp" "${output}"
}

normalize_gwas_catalog() {
  local input="$1"
  local output="$2"
  local body="${output}.body.tmp"
  gzip -dc "${input}" | awk -F '\t' -v OFS='\t' -v maxp="${MAX_P}" '
    NR == 1 {
      for (i = 1; i <= NF; i++) h[$i] = i
      required[1]="hm_rsid"; required[2]="hm_chrom"; required[3]="hm_pos"
      required[4]="hm_effect_allele"; required[5]="hm_other_allele"
      required[6]="hm_beta"; required[7]="p_value"
      for (i = 1; i <= 7; i++) if (!(required[i] in h)) {
        print "ERROR: missing GWAS Catalog field " required[i] > "/dev/stderr"; exit 13
      }
      next
    }
    {
      id=$(h["hm_rsid"]); chr=$(h["hm_chrom"]); pos=$(h["hm_pos"])
      a1=toupper($(h["hm_effect_allele"])); a2=toupper($(h["hm_other_allele"]))
      beta=$(h["hm_beta"])+0; p=$(h["p_value"])+0
      if (chr ~ /^[0-9]+$/ && chr >= 1 && chr <= 22 && id ~ /^rs[0-9]+$/ &&
          p > 0 && p <= maxp && a1 ~ /^[ACGT]+$/ && a2 ~ /^[ACGT]+$/) {
        print id, chr, pos, a1, a2, beta, p
      }
    }
  ' | LC_ALL=C sort -t $'\t' -k2,2n -k1,1 -k7,7g | awk -F '\t' -v OFS='\t' '
    $1 != previous { print; previous=$1 }
  ' > "${body}"
  { printf 'ID\tCHR\tPOS\tA1\tA2\tBETA\tP\n'; cat "${body}"; } | gzip -c > "${output}.tmp"
  rm -f "${body}"
  mv "${output}.tmp" "${output}"
}

tail -n +2 "${SOURCE_FILE}" | while IFS=$'\t' read -r outcome_id outcome_label source_kind source_id build url provenance source_status; do
  [ -n "${outcome_id}" ] || continue
  raw_file="${RAW_DIR}/${outcome_id}.${source_id}.gz"
  normalized_file="${NORMALIZED_DIR}/${outcome_id}.maxp_${MAX_P}.tsv.gz"

  echo "===== ${outcome_id}: ${source_id} ====="
  if [ -s "${normalized_file}" ] && [ "${RESUME}" = "1" ]; then
    echo "# reuse normalized GWAS without requiring the large raw file: ${normalized_file}"
    gzip -t "${normalized_file}"
  else
    if [ ! -s "${raw_file}" ]; then
      curl --fail --location --retry 8 --retry-delay 5 --retry-all-errors \
        --continue-at - --output "${raw_file}" "${url}"
    elif [ "${RESUME}" = "1" ]; then
      echo "# resume/reuse downloaded GWAS: ${raw_file}"
      curl --fail --location --retry 8 --retry-delay 5 --retry-all-errors \
        --continue-at - --output "${raw_file}" "${url}"
    fi
    gzip -t "${raw_file}"

    case "${source_kind}" in
      finngen_r9) normalize_finngen "${raw_file}" "${normalized_file}" ;;
      gwas_catalog) normalize_gwas_catalog "${raw_file}" "${normalized_file}" ;;
      *) echo "ERROR: unsupported source_kind=${source_kind}" >&2; exit 14 ;;
    esac
  fi

  retained=$(( $(gzip -dc "${normalized_file}" | wc -l) - 1 ))
  if [ "${retained}" -lt 1 ]; then
    echo "ERROR: no variants survived normalization for ${outcome_id}" >&2
    exit 15
  fi
  checksum="$(checksum_file "${normalized_file}")"
  printf '%s\t%s\tPASS\t%s\t%s\t%s\t%s\t%s\n' \
    "${outcome_id}" "${source_id}" "${raw_file}" "${normalized_file}" \
    "${retained}" "${checksum}" "$(timestamp_iso)" >> "${status_file}"

  split_dir="${NORMALIZED_DIR}/${outcome_id}"
  mkdir -p "${split_dir}"
  for chr in $(seq 1 22); do
    chr_file="${split_dir}/chr${chr}.tsv.gz"
    if [ -s "${chr_file}" ] && [ "${RESUME}" = "1" ]; then
      continue
    fi
    gzip -dc "${normalized_file}" | awk -F '\t' -v OFS='\t' -v chr="${chr}" \
      'NR == 1 || $2 == chr' | gzip -c > "${chr_file}.tmp"
    mv "${chr_file}.tmp" "${chr_file}"
  done
done

echo "GWAS preparation complete: ${NORMALIZED_DIR}"
