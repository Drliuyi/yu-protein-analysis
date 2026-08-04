#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(survival)
})

`%||%` <- function(x, y) if (is.null(x)) y else x
parse_args <- function(x) {
  out <- list()
  for (a in x) {
    p <- strsplit(sub("^--", "", a), "=", fixed = TRUE)[[1L]]
    out[[p[[1L]]]] <- if (length(p) > 1L) paste(p[-1L], collapse = "=") else TRUE
  }
  out
}

opt <- parse_args(commandArgs(trailingOnly = TRUE))
required <- c("phase1_cache", "phase3b_project", "out_dir")
missing <- required[!nzchar(vapply(required, function(x) as.character(opt[[x]] %||% ""), character(1)))]
if (length(missing)) stop("Missing arguments: ", paste(missing, collapse = ", "), call. = FALSE)
workers <- as.integer(opt$workers %||% 8L)
split_seed <- as.integer(opt$split_seed %||% 20260715L)
inner_seed <- as.integer(opt$inner_seed %||% 20260716L)
train_fraction <- as.numeric(opt$train_fraction %||% (2 / 3))
if (!is.finite(train_fraction) || train_fraction <= 0 || train_fraction >= 1) {
  stop("train_fraction must be between zero and one.", call. = FALSE)
}

source(file.path(opt$phase3b_project, "R", "00_utils.R"))
source(file.path(opt$phase3b_project, "R", "01_fold_yys.R"))

dir.create(opt$out_dir, recursive = TRUE, showWarnings = FALSE)
qc_dir <- file.path(opt$out_dir, "qc")
dir.create(qc_dir, recursive = TRUE, showWarnings = FALSE)

cat("Loading local CAD Phase 1 bundle: ", opt$phase1_cache, "\n", sep = "")
bundle <- readRDS(opt$phase1_cache)
target <- as.data.table(bundle$target)
yang <- as.data.table(bundle$yang)
proteins <- as.character(bundle$proteins)
target[, eid := as.character(eid)]
yang[, eid := as.character(eid)]

clinical_vars <- c("age", "sex", "smoking", "sbp", "bp_treatment", "diabetes",
                   "total_cholesterol", "hdl")
phase_vars <- c("age", "sex", "center", "tdi", "PC1", "PC2")
required_target <- unique(c("eid", "event", "time", "b2e", clinical_vars, phase_vars, proteins))
required_yang <- unique(c("eid", "b2e", phase_vars, proteins))
if (length(setdiff(required_target, names(target)))) {
  stop("Target missing required columns: ", paste(setdiff(required_target, names(target)), collapse = ", "), call. = FALSE)
}
if (length(setdiff(required_yang, names(yang)))) {
  stop("Yang auxiliary cohort missing required columns: ", paste(setdiff(required_yang, names(yang)), collapse = ", "), call. = FALSE)
}
if (nrow(target) != 37127L || sum(target$event) != 3442L) {
  stop("Local CAD cohort contract failed: expected 37,127 participants and 3,442 events.", call. = FALSE)
}
if (nrow(yang) != 1766L) stop("Expected 1,766 prevalent-CAD Yang participants.", call. = FALSE)
if (length(proteins) != 2910L || anyDuplicated(proteins)) stop("Expected 2,910 unique proteins.", call. = FALSE)
if (length(intersect(target$eid, yang$eid))) stop("Incident target and Yang auxiliary EIDs overlap.", call. = FALSE)

set.seed(split_seed)
shuffled <- sample(target$eid)
n_train <- floor(length(shuffled) * train_fraction)
train_ids <- shuffled[seq_len(n_train)]
test_ids <- shuffled[-seq_len(n_train)]
derivation <- target[match(train_ids, eid)]
holdout <- target[match(test_ids, eid)]
if (anyNA(derivation$eid) || anyNA(holdout$eid) || length(intersect(train_ids, test_ids))) {
  stop("Derivation/hold-out split contract failed.", call. = FALSE)
}

set.seed(inner_seed)
inner_fold <- sample(rep(seq_len(10L), length.out = nrow(derivation)))
fold_table <- data.table(eid = derivation$eid, inner_fold = inner_fold)
if (any(table(inner_fold, derivation$event) == 0L)) stop("A derivation inner fold lacks an event class.", call. = FALSE)

cfg <- list(
  stable_control_min_followup_years = as.numeric(bundle$stable_control_min_followup_years %||% 10),
  protein_missing_fraction_max = 0.20,
  protein_variance_min = 1.0e-8,
  phase_covariates = phase_vars,
  phase_categorical = c("sex", "center"),
  fdr_threshold = 0.05,
  time_breaks = c(-16, -10, -5, -3, -1, 0, 1, 3, 5, 10, 16),
  time_labels = c("-16 to -10", "-10 to -5", "-5 to -3", "-3 to -1", "-1 to 0",
                  "0 to 1", "1 to 3", "3 to 5", "5 to 10", "10 to 16"),
  min_individuals_per_bin = 20L,
  winsor_lower = 0.001,
  winsor_upper = 0.999,
  component_floor = 0.05,
  epsilon_C = 1.0e-8,
  epsilon_D = 1.0e-8
)

cat("Computing derivation-only Yin ProtWAS and ABCD-YYS v2 with workers=", workers, "\n", sep = "")
built <- p3b_build_fold_yys(derivation, yang, proteins, cfg, workers = workers, chunk_size = 100L)
if (nrow(built$score) != 2910L) stop("Not all 2,910 proteins passed derivation QC.", call. = FALSE)
score <- built$score[match(proteins, protein)]
score[, p_bonferroni := pmin(1, p_yin * length(proteins))]
score[, derivation_bonferroni_candidate := is.finite(p_yin) & p_yin < 0.05 / length(proteins)]

metadata <- rbindlist(list(
  derivation[, c("eid", "event", "time", clinical_vars), with = FALSE][, split := "derivation"],
  holdout[, c("eid", "event", "time", clinical_vars), with = FALSE][, split := "holdout"]
), use.names = TRUE)
metadata <- merge(metadata, fold_table, by = "eid", all.x = TRUE, sort = FALSE)
metadata <- metadata[match(c(derivation$eid, holdout$eid), eid)]
metadata[split == "holdout", inner_fold := NA_integer_]

fwrite(metadata, file.path(opt$out_dir, "target_metadata.csv.gz"))
fwrite(data.table(feature_index = seq_along(proteins) - 1L, protein = proteins),
       file.path(opt$out_dir, "protein_order.csv"))
fwrite(score, file.path(opt$out_dir, "cad_derivation_ABCD_YYS_v2.csv.gz"))
fwrite(built$trajectory, file.path(opt$out_dir, "cad_derivation_trajectory.csv.gz"))
fwrite(built$candidate_qc, file.path(qc_dir, "protein_qc.csv"))
fwrite(fold_table, file.path(opt$out_dir, "derivation_inner_folds.csv"))
fwrite(data.table(eid = derivation$eid), file.path(opt$out_dir, "derivation_eid.csv"))
fwrite(data.table(eid = holdout$eid), file.path(opt$out_dir, "holdout_eid.csv"))

component_qc <- rbindlist(lapply(c("A", "B", "C", "D", "YYS_v2"), function(v) {
  x <- score[[v]]
  data.table(
    component = v,
    n = length(x),
    missing_n = sum(!is.finite(x)),
    unique_n = uniqueN(x),
    min = min(x),
    max = max(x),
    sd = sd(x),
    status = if (all(is.finite(x)) && sd(x) > 0 && min(x) >= 0.05 && max(x) <= 1) "PASS" else "FAIL"
  )
}))
fwrite(component_qc, file.path(qc_dir, "abcd_yys_component_qc.csv"))
if (any(component_qc$status == "FAIL")) stop("ABCD-YYS v2 component QC failed.", call. = FALSE)

split_hash <- digest::digest(paste(c(sort(train_ids), "HOLDOUT", sort(test_ids)), collapse = "\n"),
                             algo = "sha256", serialize = FALSE)
writeLines(split_hash, file.path(opt$out_dir, "split_hash.txt"))
manifest <- data.table(
  item = c("status", "analysis", "target_n", "target_events", "derivation_n", "derivation_events",
           "holdout_n", "holdout_events", "yang_n", "protein_n", "bonferroni_threshold",
           "bonferroni_candidate_n", "inner_folds", "split_seed", "inner_seed", "split_hash",
           "phase1_cache_md5"),
  value = c("PASS", "local CAD Yu-style derivation/hold-out plus ABCD-YYS v2",
            nrow(target), sum(target$event), nrow(derivation), sum(derivation$event),
            nrow(holdout), sum(holdout$event), nrow(yang), length(proteins),
            0.05 / length(proteins), sum(score$derivation_bonferroni_candidate), 10L,
            split_seed, inner_seed, split_hash, unname(tools::md5sum(opt$phase1_cache)))
)
fwrite(manifest, file.path(opt$out_dir, "input_manifest.csv"))
cat("PASS: derivation-only CAD ProtWAS and ABCD-YYS v2 prepared at ", opt$out_dir, "\n", sep = "")
