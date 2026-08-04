#!/usr/bin/env Rscript

suppressWarnings(suppressPackageStartupMessages(library(data.table)))

args <- commandArgs(trailingOnly = TRUE)
analysis_dir <- if (length(args)) args[[1]] else "D:/UKB_data/analysis/yu_proteomic_repo"
cox_dir <- file.path(analysis_dir, "05_cox")
required <- c(
  "scope", "outcome_id", "feature_id", "n", "events", "beta", "se", "z", "p",
  "hr", "ci_low", "ci_high", "bonferroni_significant"
)

read_scope <- function(prefix) {
  files <- list.files(
    cox_dir, pattern = paste0("^", prefix, ".*_cox[.]csv[.]gz$"),
    full.names = TRUE
  )
  if (length(files) != 14L) {
    stop(prefix, " expected 14 shard files, found ", length(files), call. = FALSE)
  }
  rows <- lapply(files, function(path) {
    x <- fread(path, showProgress = FALSE)
    missing <- setdiff(required, names(x))
    if (length(missing)) {
      stop(basename(path), " missing columns: ", paste(missing, collapse = ", "), call. = FALSE)
    }
    if (nrow(x) == 0L || anyDuplicated(x$feature_id)) {
      stop(basename(path), " has zero rows or duplicate feature IDs.", call. = FALSE)
    }
    x
  })
  hashes <- vapply(rows, function(x) paste(sort(x$feature_id), collapse = "\n"), character(1))
  if (length(unique(hashes)) != 1L) stop(prefix, " shard protein sets are inconsistent.", call. = FALSE)
  rbindlist(rows, use.names = TRUE, fill = TRUE)
}

full <- read_scope("full_incident_")
derivation <- read_scope("derivation_")
if (!identical(sort(unique(full$feature_id)), sort(unique(derivation$feature_id)))) {
  stop("Full and derivation protein panels differ.", call. = FALSE)
}

full_summary <- full[, .(
  full_n = unique(n)[1],
  full_events = unique(events)[1],
  proteins_tested = .N,
  full_significant_associations = sum(bonferroni_significant, na.rm = TRUE),
  full_unique_significant_proteins = uniqueN(feature_id[bonferroni_significant == TRUE])
), by = outcome_id]

derivation_summary <- derivation[, .(
  derivation_n = unique(n)[1],
  derivation_events = unique(events)[1],
  derivation_significant_associations = sum(bonferroni_significant, na.rm = TRUE),
  derivation_unique_significant_proteins = uniqueN(feature_id[bonferroni_significant == TRUE])
), by = outcome_id]

summary <- merge(full_summary, derivation_summary, by = "outcome_id")
setorder(summary, -full_significant_associations, outcome_id)
print(summary)
cat(
  "QC_STATUS=PASS",
  "FULL_TOTAL_ASSOCIATIONS=", sum(full$bonferroni_significant, na.rm = TRUE),
  "FULL_UNIQUE_PROTEINS=", uniqueN(full[bonferroni_significant == TRUE, feature_id]),
  "DERIVATION_TOTAL_ASSOCIATIONS=", sum(derivation$bonferroni_significant, na.rm = TRUE),
  "DERIVATION_UNIQUE_PROTEINS=", uniqueN(derivation[bonferroni_significant == TRUE, feature_id]),
  "PANEL_SIZE=", uniqueN(full$feature_id),
  "\n"
)
