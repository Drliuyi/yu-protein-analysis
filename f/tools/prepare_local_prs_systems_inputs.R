#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(name, default = NULL) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (!length(hit)) return(default)
  sub(paste0("^--", name, "="), "", hit[[1]])
}

input <- arg_value("input")
out_dir <- arg_value("out_dir")
if (is.null(input) || !file.exists(input)) stop("Missing --input=<prs_protein_associations.csv.gz>")
if (is.null(out_dir)) stop("Missing --out_dir=<14_enrichment/local_prs_inputs>")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

x <- fread(input)
required <- c(
  "outcome_id", "feature_id", "protein", "panel", "olink_id", "threshold",
  "beta", "p", "bonferroni_significant"
)
missing <- setdiff(required, names(x))
if (length(missing)) stop("PRS association matrix lacks: ", paste(missing, collapse = ", "))
x[, bonferroni_significant := as.logical(bonferroni_significant)]

background <- x[, .(
  protein = protein[[1]], panel = panel[[1]], olink_id = olink_id[[1]],
  tested_endpoints = uniqueN(outcome_id), tested_threshold_rows = .N
), by = feature_id][order(protein, feature_id)]

significant_thresholds <- x[bonferroni_significant %in% TRUE]
pair_best <- significant_thresholds[order(p)][, .SD[1], by = .(outcome_id, feature_id)]
pair_best <- pair_best[, .(
  outcome_id, feature_id, protein, panel, olink_id,
  best_threshold = threshold, beta, p, bonferroni_threshold
)][order(outcome_id, p)]

foreground <- pair_best[, .(
  protein = protein[[1]], panel = panel[[1]], olink_id = olink_id[[1]],
  significant_endpoints_n = uniqueN(outcome_id),
  significant_endpoints = paste(sort(unique(outcome_id)), collapse = ";"),
  min_p = min(p, na.rm = TRUE),
  max_abs_beta = max(abs(beta), na.rm = TRUE)
), by = feature_id][order(min_p, protein)]

fwrite(background, file.path(out_dir, "prs_systems_background_all_tested_proteins.csv"))
fwrite(foreground, file.path(out_dir, "prs_systems_foreground_significant_any_outcome.csv"))
fwrite(pair_best, file.path(out_dir, "prs_systems_disease_specific_pairs.csv"))
fwrite(significant_thresholds, file.path(out_dir, "prs_systems_significant_threshold_evidence.csv.gz"))

manifest <- list(
  status = "PASS",
  input = normalizePath(input, winslash = "/"),
  association_rows = nrow(x),
  outcomes_tested = uniqueN(x$outcome_id),
  background_proteins = nrow(background),
  significant_threshold_rows = nrow(significant_thresholds),
  significant_outcome_protein_pairs = nrow(pair_best),
  foreground_unique_proteins = nrow(foreground),
  significant_outcomes = uniqueN(pair_best$outcome_id),
  foreground_rule = "Bonferroni significant at any tested PRS threshold in any local outcome",
  background_rule = "All proteins tested in the local PRS-protein association matrix",
  generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)
write_json(manifest, file.path(out_dir, "prs_systems_input_manifest.json"), pretty = TRUE, auto_unbox = TRUE)
cat(toJSON(manifest, pretty = TRUE, auto_unbox = TRUE), "\n")
