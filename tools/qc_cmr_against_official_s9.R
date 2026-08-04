#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(readxl)
})

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(name, default = NULL) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (!length(hit)) return(default)
  sub(paste0("^--", name, "="), "", hit[[1]])
}

local_file <- arg_value("local")
official_file <- arg_value("official")
out_dir <- arg_value("out_dir", dirname(local_file))
if (is.null(local_file) || !file.exists(local_file)) stop("Missing --local=<cmr_associations.csv.gz>")
if (is.null(official_file) || !file.exists(official_file)) stop("Missing --official=<supplementary_table.xlsx>")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

key <- function(x) toupper(gsub("[^A-Z0-9]", "", as.character(x)))
local <- fread(local_file)
official <- as.data.table(read_excel(official_file, sheet = "S9", skip = 1))
setnames(official, c("β", "P value"), c("beta", "p"))
local[, protein_key := key(Protein)]
official[, protein_key := key(Protein)]

# The published table identifies proteins by symbol, while the local matrix
# retains assay-level IDs. Median aggregation prevents duplicate-symbol
# Cartesian joins from inflating concordance counts.
local_unique <- local[, .(
  beta_local = median(as.numeric(beta), na.rm = TRUE),
  p_local = min(as.numeric(p), na.rm = TRUE),
  local_assays = uniqueN(feature_id)
), by = .(Outcome, protein_key)]
official_unique <- official[, .(
  beta_official = median(as.numeric(beta), na.rm = TRUE),
  p_official = min(as.numeric(p), na.rm = TRUE),
  official_rows = .N
), by = .(Outcome, protein_key)]
matched <- merge(local_unique, official_unique, by = c("Outcome", "protein_key"))

metric_qc <- matched[, .(
  matched_pairs = .N,
  beta_pearson = cor(beta_local, beta_official, use = "complete.obs"),
  beta_spearman = cor(beta_local, beta_official, use = "complete.obs", method = "spearman"),
  direction_concordance = mean(sign(beta_local) == sign(beta_official), na.rm = TRUE)
), by = Outcome][order(Outcome)]
fwrite(metric_qc, file.path(out_dir, "cmr_official_s9_concordance_by_metric.csv"))

summary <- list(
  status = if (nrow(metric_qc) == 19L && all(metric_qc$beta_pearson > 0)) "PASS" else "FAIL",
  matched_unique_pairs = nrow(matched),
  matched_outcomes = uniqueN(matched$Outcome),
  matched_unique_proteins = uniqueN(matched$protein_key),
  beta_pearson = unname(cor(matched$beta_local, matched$beta_official, use = "complete.obs")),
  beta_spearman = unname(cor(matched$beta_local, matched$beta_official, use = "complete.obs", method = "spearman")),
  direction_concordance = unname(mean(sign(matched$beta_local) == sign(matched$beta_official), na.rm = TRUE)),
  local_source = normalizePath(local_file, winslash = "/"),
  official_source = normalizePath(official_file, winslash = "/"),
  generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)
write_json(summary, file.path(out_dir, "cmr_official_s9_concordance_summary.json"), pretty = TRUE, auto_unbox = TRUE)
cat(toJSON(summary, pretty = TRUE, auto_unbox = TRUE), "\n")
