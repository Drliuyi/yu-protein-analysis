#!/usr/bin/env bash
set -euo pipefail

export PATH="/home/laungai/miniforge3/bin:${PATH}"

PROJECT_DIR="${PROJECT_DIR:-/mnt/d/scripts/yy_cad_yu_yys}"
ANALYSIS_DIR="${ANALYSIS_DIR:-/mnt/d/analysis/yu_proteomic_repo_v3}"
SOURCE_FILE="${SOURCE_FILE:-${PROJECT_DIR}/f/config/prs_gwas_sources.tsv}"
THRESHOLD_FILE="${THRESHOLD_FILE:-${PROJECT_DIR}/f/config/prs_thresholds.tsv}"
PRS_DIR="${PRS_DIR:-${ANALYSIS_DIR}/13_prs}"
GWAS_DIR="${PRS_DIR}/gwas_normalized"
SCORE_DIR="${PRS_DIR}/scores"
INPUT_DIR="${PRS_DIR}/inputs"
STREAM_DIR="${PRS_DIR}/genotype_stream"
KEEP_FILE="${INPUT_DIR}/target.keep.tsv"
NAS_ROOT="${NAS_ROOT:-/tmp/zfsv3/sata11/13283546638/data/projects/genotype_pc_nas/imputed_pgen_autosomes}"
DIRECT_NAS_ROOT="${DIRECT_NAS_ROOT:-/mnt/z/projects/genotype_pc_nas/imputed_pgen_autosomes}"
GENOTYPE_MODE="${GENOTYPE_MODE:-auto}"
THREADS="${THREADS:-16}"
MEMORY_MB="${MEMORY_MB:-48000}"
START_CHR="${START_CHR:-1}"
END_CHR="${END_CHR:-22}"
MAX_P="${MAX_P:-0.0005}"
CLUMP_R2="${CLUMP_R2:-0.1}"
CLUMP_KB="${CLUMP_KB:-250}"
CLEAN_GENOTYPE="${CLEAN_GENOTYPE:-1}"
RESUME="${RESUME:-1}"
SCORE_JOBS="${SCORE_JOBS:-2}"
BATCH_HELPER="${BATCH_HELPER:-${PROJECT_DIR}/f/tools/build_batched_prs_score.py}"

mkdir -p "${SCORE_DIR}" "${STREAM_DIR}" "${PRS_DIR}/qc"

for command_name in plink2 awk gzip sort stat python3; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "ERROR: required command is unavailable: ${command_name}" >&2
    exit 1
  }
done
[ -s "${BATCH_HELPER}" ] || { echo "ERROR: missing batch score helper: ${BATCH_HELPER}" >&2; exit 1; }

case "${GENOTYPE_MODE}" in
  auto)
    if [ -s "${DIRECT_NAS_ROOT}/chr1/pgen/chr1_imp.pgen" ]; then
      GENOTYPE_MODE="directnas"
    else
      GENOTYPE_MODE="streamzspace"
    fi
    ;;
  directnas|streamzspace) ;;
  *) echo "ERROR: GENOTYPE_MODE must be auto, directnas, or streamzspace." >&2; exit 1 ;;
esac
if [ "${GENOTYPE_MODE}" = "streamzspace" ]; then
  for command_name in ssh rsync; do
    command -v "${command_name}" >/dev/null 2>&1 || {
      echo "ERROR: required streaming command is unavailable: ${command_name}" >&2
      exit 1
    }
  done
fi
echo "# genotype mode: ${GENOTYPE_MODE}"
echo "# direct NAS root: ${DIRECT_NAS_ROOT}"
echo "# streaming source: zspace:${NAS_ROOT}"
for required_file in "${SOURCE_FILE}" "${THRESHOLD_FILE}" "${KEEP_FILE}"; do
  [ -s "${required_file}" ] || { echo "ERROR: missing required file: ${required_file}" >&2; exit 2; }
done

mapfile -t score_columns < <(tail -n +2 "${THRESHOLD_FILE}" | awk -F '\t' '{print $3}')
mapfile -t thresholds < <(tail -n +2 "${THRESHOLD_FILE}" | awk -F '\t' '{print $1}')
if [ "${#score_columns[@]}" -ne 5 ] || [ "${#thresholds[@]}" -ne 5 ]; then
  echo "ERROR: expected exactly five PRS thresholds." >&2
  exit 3
fi

remote_size() {
  ssh zspace "stat -c%s '$1'"
}

ensure_local_copy() {
  local chr="$1" ext="$2"
  local remote="${NAS_ROOT}/chr${chr}/pgen/chr${chr}_imp.${ext}"
  local local_file="${STREAM_DIR}/chr${chr}/chr${chr}_imp.${ext}"
  local expected observed
  mkdir -p "${STREAM_DIR}/chr${chr}"
  expected="$(remote_size "${remote}")"
  observed=0
  [ -s "${local_file}" ] && observed="$(stat -c%s "${local_file}")"
  if [ "${observed}" != "${expected}" ]; then
    rm -f "${local_file}"
    rsync -avP --inplace --no-perms --no-owner --no-group "zspace:${remote}" "${local_file}"
  fi
  observed="$(stat -c%s "${local_file}")"
  [ "${observed}" = "${expected}" ] || {
    echo "ERROR: copied chr${chr}.${ext} size mismatch: ${observed} != ${expected}" >&2
    exit 4
  }
}

extract_clump_ids() {
  local clumps="$1" output="$2"
  awk -F '\t' '
    NR == 1 { for (i=1; i<=NF; i++) if ($i == "ID") idcol=i; next }
    idcol > 0 && $idcol != "" { print $idcol }
  ' "${clumps}" | sort -u > "${output}"
}

write_zero_sscore() {
  local output="$1"
  awk -F '\t' -v OFS='\t' -v c1="${score_columns[0]}" -v c2="${score_columns[1]}" \
      -v c3="${score_columns[2]}" -v c4="${score_columns[3]}" -v c5="${score_columns[4]}" '
    NR == 1 { print "#FID","IID",c1 "_SUM",c2 "_SUM",c3 "_SUM",c4 "_SUM",c5 "_SUM"; next }
    { print $1,$2,0,0,0,0,0 }
  ' "${KEEP_FILE}" > "${output}"
}

make_wide_score_file() {
  local gwas="$1" clump_ids="$2" output="$3"
  awk -F '\t' -v OFS='\t' \
      -v t1="${thresholds[0]}" -v t2="${thresholds[1]}" -v t3="${thresholds[2]}" \
      -v t4="${thresholds[3]}" -v t5="${thresholds[4]}" \
      -v c1="${score_columns[0]}" -v c2="${score_columns[1]}" -v c3="${score_columns[2]}" \
      -v c4="${score_columns[3]}" -v c5="${score_columns[4]}" '
    FILENAME == ARGV[1] { keep[$1]=1; next }
    FILENAME == ARGV[2] {
      if (FNR == 1) {
        for (i=1; i<=NF; i++) h[$i]=i
        print "ID","A1",c1,c2,c3,c4,c5
        next
      }
      id=$(h["ID"]); p=$(h["P"])+0; beta=$(h["BETA"])+0
      if (id in keep) print id,$(h["A1"]),(p<=t1?beta:0),(p<=t2?beta:0),(p<=t3?beta:0),(p<=t4?beta:0),(p<=t5?beta:0)
    }
  ' "${clump_ids}" <(gzip -dc "${gwas}") > "${output}"
}

status_file="${PRS_DIR}/score_status.tsv"
variant_file="${PRS_DIR}/score_variant_counts.tsv"
[ -f "${status_file}" ] || printf 'outcome_id\tchr\tstatus\tsscore\tcompleted_at\n' > "${status_file}"
[ -f "${variant_file}" ] || printf 'outcome_id\tchr\tthreshold\tscore_column\tvariant_count\n' > "${variant_file}"

if ! [[ "${SCORE_JOBS}" =~ ^[0-9]+$ ]] || [ "${SCORE_JOBS}" -lt 1 ]; then
  echo "ERROR: SCORE_JOBS must be a positive integer." >&2
  exit 3
fi
if [ "${GENOTYPE_MODE}" = "streamzspace" ] && [ "${SCORE_JOBS}" -gt 1 ]; then
  echo "# streamzspace uses one chromosome at a time to protect D-drive scratch space"
  SCORE_JOBS=1
fi
SCORE_JOBS=$(( SCORE_JOBS < (END_CHR - START_CHR + 1) ? SCORE_JOBS : (END_CHR - START_CHR + 1) ))
JOB_THREADS=$(( THREADS / SCORE_JOBS ))
[ "${JOB_THREADS}" -ge 1 ] || JOB_THREADS=1
JOB_MEMORY_MB=$(( MEMORY_MB / SCORE_JOBS ))
[ "${JOB_MEMORY_MB}" -ge 2048 ] || JOB_MEMORY_MB=2048
echo "# chromosome jobs: ${SCORE_JOBS}; threads/job: ${JOB_THREADS}; memory/job: ${JOB_MEMORY_MB} MB"
echo "# each chromosome is scored once for all incomplete outcome x threshold columns"

append_variant_counts_from_score() {
  local outcome_id="$1" chr="$2" score_file="$3" output="$4"
  local index count
  [ -s "${score_file}" ] || {
    echo "ERROR: completed score is missing its variant source file: ${score_file}" >&2
    return 1
  }
  for index in 0 1 2 3 4; do
    count="$(awk -F '\t' -v col=$((index+3)) 'NR>1 && $col != 0 {n++} END{print n+0}' "${score_file}")"
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "${outcome_id}" "${chr}" "${thresholds[$index]}" "${score_columns[$index]}" "${count}" >> "${output}"
  done
}

process_chr() {
  local chr="$1"
  local chr_stream geno_prefix need_bytes free_bytes margin unique_ids
  local batch_dir manifest batch_score batch_prefix batch_sscore batch_qc unresolved
  local local_status local_variants batch_outcomes score_last_column
  local outcome_id outcome_label source_kind source_id build url provenance source_status
  local gwas outdir out_prefix sscore marker score_file gwas_rows clump_prefix clumps clump_ids

  echo "===== prepare and batch-score chromosome ${chr} ====="
  chr_stream="${STREAM_DIR}/chr${chr}"
  batch_dir="${SCORE_DIR}/_batched/chr${chr}"
  mkdir -p "${chr_stream}" "${batch_dir}"
  local_status="${batch_dir}/score_status.tsv"
  local_variants="${batch_dir}/score_variant_counts.tsv"
  printf 'outcome_id\tchr\tstatus\tsscore\tcompleted_at\n' > "${local_status}"
  printf 'outcome_id\tchr\tthreshold\tscore_column\tvariant_count\n' > "${local_variants}"

  if [ "${GENOTYPE_MODE}" = "directnas" ]; then
    geno_prefix="${DIRECT_NAS_ROOT}/chr${chr}/pgen/chr${chr}_imp"
    for ext in pgen pvar psam; do
      [ -s "${geno_prefix}.${ext}" ] || {
        echo "ERROR: direct NAS genotype is missing: ${geno_prefix}.${ext}" >&2
        return 5
      }
    done
  else
    geno_prefix="${chr_stream}/chr${chr}_imp"
    need_bytes=0
    for ext in pgen pvar psam; do
      need_bytes=$((need_bytes + $(remote_size "${NAS_ROOT}/chr${chr}/pgen/chr${chr}_imp.${ext}")))
    done
    free_bytes="$(df -PB1 "${STREAM_DIR}" | awk 'NR==2 {print $4}')"
    margin=$((10 * 1024 * 1024 * 1024))
    [ "${free_bytes}" -ge $((need_bytes + margin)) ] || {
      echo "ERROR: insufficient D-drive scratch for chr${chr}; need $(( (need_bytes+margin)/1024/1024/1024 )) GiB." >&2
      return 5
    }
    ensure_local_copy "${chr}" pvar
    ensure_local_copy "${chr}" psam
    ensure_local_copy "${chr}" pgen
  fi

  unique_ids="${chr_stream}/chr${chr}.unique.ids"
  if [ ! -s "${unique_ids}" ]; then
    awk -F '\t' '$0 !~ /^#/ && $3!="" && $3!="." {n[$3]++} END {for(id in n) if(n[id]==1) print id}' \
      "${geno_prefix}.pvar" | sort > "${unique_ids}"
  fi
  [ -s "${unique_ids}" ] || { echo "ERROR: no unique variant IDs for chr${chr}" >&2; return 5; }

  manifest="${batch_dir}/batch_manifest.tsv"
  printf 'outcome_id\tscore_file\toutput_sscore\tmarker\n' > "${manifest}"
  batch_outcomes=0
  while IFS=$'\t' read -r outcome_id outcome_label source_kind source_id build url provenance source_status; do
    [ -n "${outcome_id}" ] || continue
    outcome_id="${outcome_id%$'\r'}"
    gwas="${GWAS_DIR}/${outcome_id}/chr${chr}.tsv.gz"
    [ -s "${gwas}" ] || { echo "ERROR: missing normalized GWAS: ${gwas}" >&2; return 6; }
    outdir="${SCORE_DIR}/${outcome_id}/chr${chr}"
    mkdir -p "${outdir}"
    out_prefix="${outdir}/${outcome_id}_chr${chr}"
    sscore="${out_prefix}.sscore"
    marker="${out_prefix}.done"
    score_file="${out_prefix}.wide_score.tsv"

    if [ -s "${sscore}" ] && [ -s "${marker}" ] && [ "${RESUME}" = "1" ]; then
      echo "# reuse completed ${outcome_id} chr${chr}"
      append_variant_counts_from_score "${outcome_id}" "${chr}" "${score_file}" "${local_variants}"
      printf '%s\t%s\tPASS\t%s\t%s\n' "${outcome_id}" "${chr}" "${sscore}" "$(date -Is)" >> "${local_status}"
      continue
    fi

    clump_prefix="${out_prefix}.clump"
    clumps="${clump_prefix}.clumps"
    clump_ids="${out_prefix}.clumped.ids"
    if ! { [ "${RESUME}" = "1" ] && [ -s "${score_file}" ] && [ -f "${clump_ids}" ]; }; then
      gwas_rows=$(( $(gzip -dc "${gwas}" | wc -l) - 1 ))
      if [ "${gwas_rows}" -gt 0 ]; then
        plink2 --pfile "${geno_prefix}" --extract "${unique_ids}" \
          --clump "${gwas}" --clump-id-field ID --clump-p-field P --clump-a1-field A1 \
          --clump-force-a1 --clump-p1 "${MAX_P}" --clump-p2 "${MAX_P}" \
          --clump-r2 "${CLUMP_R2}" --clump-kb "${CLUMP_KB}" \
          --threads "${JOB_THREADS}" --memory "${JOB_MEMORY_MB}" --out "${clump_prefix}"
        [ -s "${clumps}" ] && extract_clump_ids "${clumps}" "${clump_ids}" || : > "${clump_ids}"
      else
        : > "${clump_ids}"
      fi
      make_wide_score_file "${gwas}" "${clump_ids}" "${score_file}"
    else
      echo "# reuse clumping/weights ${outcome_id} chr${chr}"
    fi
    [ -s "${score_file}" ] || { echo "ERROR: missing score weights: ${score_file}" >&2; return 6; }
    printf '%s\t%s\t%s\t%s\n' "${outcome_id}" "${score_file}" "${sscore}" "${marker}" >> "${manifest}"
    batch_outcomes=$((batch_outcomes + 1))
  done < <(tail -n +2 "${SOURCE_FILE}")

  if [ "${batch_outcomes}" -gt 0 ]; then
    batch_score="${batch_dir}/chr${chr}.combined_score.tsv"
    batch_prefix="${batch_dir}/chr${chr}.combined"
    batch_sscore="${batch_prefix}.sscore"
    batch_qc="${batch_dir}/batch_qc.tsv"
    unresolved="${batch_dir}/unresolved_alleles.tsv"
    python3 "${BATCH_HELPER}" build \
      --manifest "${manifest}" --thresholds "${THRESHOLD_FILE}" \
      --pvar "${geno_prefix}.pvar" --output "${batch_score}" \
      --qc "${batch_qc}" --unresolved "${unresolved}"

    score_last_column=$((2 + batch_outcomes * 5))
    plink2 --pfile "${geno_prefix}" --keep "${KEEP_FILE}" \
      --score "${batch_score}" 1 2 header-read ignore-dup-ids cols=scoresums \
      --score-col-nums "3-${score_last_column}" \
      --threads "${JOB_THREADS}" --memory "${JOB_MEMORY_MB}" --out "${batch_prefix}"
    [ -s "${batch_sscore}" ] || { echo "ERROR: missing batched score output ${batch_sscore}" >&2; return 7; }
    python3 "${BATCH_HELPER}" split \
      --manifest "${manifest}" --thresholds "${THRESHOLD_FILE}" --input "${batch_sscore}"

    awk -F '\t' -v OFS='\t' -v chr="${chr}" 'NR>1 {print $1,chr,$2,$3,$5}' \
      "${batch_qc}" >> "${local_variants}"
    while IFS=$'\t' read -r outcome_id score_file sscore marker; do
      [ -s "${sscore}" ] || { echo "ERROR: split score is missing: ${sscore}" >&2; return 7; }
      printf 'PASS\t%s\n' "$(date -Is)" > "${marker}"
      printf '%s\t%s\tPASS\t%s\t%s\n' "${outcome_id}" "${chr}" "${sscore}" "$(date -Is)" >> "${local_status}"
    done < <(tail -n +2 "${manifest}")
    printf 'PASS\t%s\toutcomes=%s\n' "$(date -Is)" "${batch_outcomes}" > "${batch_dir}/batch.done"
    rm -f "${batch_sscore}"
  else
    echo "# chromosome ${chr} already complete"
  fi

  if [ "${GENOTYPE_MODE}" = "streamzspace" ] && [ "${CLEAN_GENOTYPE}" = "1" ]; then
    rm -f "${geno_prefix}.pgen" "${geno_prefix}.pvar" "${geno_prefix}.psam" "${unique_ids}"
    rmdir "${chr_stream}" 2>/dev/null || true
  fi
  echo "===== chromosome ${chr} complete ====="
}

running_pids=()
running_chrs=()
failed=0
for chr in $(seq "${START_CHR}" "${END_CHR}"); do
  process_chr "${chr}" &
  running_pids+=("$!")
  running_chrs+=("${chr}")
  if [ "${#running_pids[@]}" -ge "${SCORE_JOBS}" ] || [ "${chr}" -eq "${END_CHR}" ]; then
    for index in "${!running_pids[@]}"; do
      if ! wait "${running_pids[$index]}"; then
        echo "ERROR: chromosome ${running_chrs[$index]} scoring failed." >&2
        failed=1
      fi
    done
    running_pids=()
    running_chrs=()
    [ "${failed}" -eq 0 ] || exit 8
  fi
done

# Refresh only the chromosome rows handled by this invocation. This avoids
# concurrent child writes and preserves status rows from earlier subset runs.
for chr in $(seq "${START_CHR}" "${END_CHR}"); do
  chr_status="${SCORE_DIR}/_batched/chr${chr}/score_status.tsv"
  chr_variants="${SCORE_DIR}/_batched/chr${chr}/score_variant_counts.tsv"
  if [ -s "${chr_status}" ]; then
    awk -F '\t' -v chr="${chr}" 'NR==1 || $2 != chr' "${status_file}" > "${status_file}.tmp"
    tail -n +2 "${chr_status}" >> "${status_file}.tmp"
    mv "${status_file}.tmp" "${status_file}"
  fi
  if [ -s "${chr_variants}" ]; then
    awk -F '\t' -v chr="${chr}" 'NR==1 || $2 != chr' "${variant_file}" > "${variant_file}.tmp"
    tail -n +2 "${chr_variants}" >> "${variant_file}.tmp"
    mv "${variant_file}.tmp" "${variant_file}"
  fi
done

echo "PRS chromosome scoring complete: ${SCORE_DIR}"
