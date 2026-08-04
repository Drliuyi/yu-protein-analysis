#!/usr/bin/env Rscript

suppressPackageStartupMessages({ library(data.table); library(survival); library(pROC) })

args <- commandArgs(trailingOnly = TRUE)
analysis_dir <- sub("^--analysis-dir=", "", args[grepl("^--analysis-dir=", args)])
if (!length(analysis_dir)) stop("--analysis-dir is required", call. = FALSE)
model_dir <- file.path(analysis_dir, "02_lightgbm")
pred <- fread(file.path(model_dir, "holdout_predictions.csv.gz"),
              colClasses = list(character = c("eid", "model_id")))

km_censor <- function(time, event) {
  fit <- survfit(Surv(time, 1L - as.integer(event)) ~ 1)
  function(t, left = FALSE) {
    tt <- if (left) pmax(0, t - 1e-10) else t
    pmax(summary(fit, times = tt, extend = TRUE)$surv, 1e-6)
  }
}
ipcw_auc <- function(time, event, score, horizon) {
  ok <- is.finite(time) & is.finite(score) & event %in% c(0L, 1L)
  time <- time[ok]; event <- event[ok]; score <- score[ok]
  cases <- which(event == 1L & time <= horizon); controls <- which(time > horizon)
  if (!length(cases) || !length(controls)) return(NA_real_)
  G <- km_censor(time, event); wc <- 1 / G(time[cases], left = TRUE)
  wn <- rep(1 / G(horizon), length(controls)); cs <- score[cases]; ns <- score[controls]
  ord <- order(ns); ns <- ns[ord]; wn <- wn[ord]; cw <- cumsum(wn)
  concord <- vapply(cs, function(s) {
    less <- findInterval(s, ns, left.open = TRUE); leq <- findInterval(s, ns)
    lower <- if (less > 0) cw[[less]] else 0
    equal <- if (leq > less) sum(wn[(less + 1L):leq]) else 0
    lower + 0.5 * equal
  }, numeric(1))
  sum(wc * concord) / (sum(wc) * sum(wn))
}
calibration <- function(event, score) {
  eps <- 1e-6; lp <- qlogis(pmin(1 - eps, pmax(eps, score)))
  sf <- suppressWarnings(glm(event ~ lp, family = binomial()))
  it <- suppressWarnings(glm(event ~ 1, family = binomial(), offset = lp))
  c(calibration_intercept = unname(coef(it)[[1L]]),
    calibration_slope = unname(coef(sf)[[2L]]))
}

horizons <- c(1, 3, 5, 10)
metrics <- pred[, {
  values <- c(
    Harrell_C = unname(concordance(Surv(time, event) ~ prediction, reverse = TRUE)$concordance),
    calibration(event, prediction)
  )
  for (h in horizons) values[[paste0("AUC_", h, "y")]] <- ipcw_auc(time, event, prediction, h)
  as.list(values)
}, by = model_id]
fwrite(metrics, file.path(model_dir, "holdout_time_dependent_metrics.csv"))

comparisons <- data.table(
  comparison = c("Protein YYScore vs YinScore", "Clinical plus protein YYScore vs YinScore",
                 "Protein YYScore vs panel", "Clinical plus protein YYScore vs panel"),
  benchmark = c("CAD_YinPanel_YinScore", "BasicClinical_CAD_YinPanel_YinScore",
                "CAD_YinPanel", "BasicClinical_CAD_YinPanel"),
  extension = c("CAD_YinPanel_YYScore", "BasicClinical_CAD_YinPanel_YYScore",
                "CAD_YinPanel_YYScore", "BasicClinical_CAD_YinPanel_YYScore")
)
delong <- comparisons[, {
  b <- pred[model_id == benchmark]; e <- pred[model_id == extension]
  setorder(b, eid); setorder(e, eid)
  if (!identical(b$eid, e$eid) || !identical(b$event, e$event)) stop("Paired test alignment failed.")
  rb <- roc(b$event, b$prediction, quiet = TRUE, direction = "<")
  re <- roc(e$event, e$prediction, quiet = TRUE, direction = "<")
  test <- roc.test(re, rb, paired = TRUE, method = "delong")
  .(AUC_benchmark = as.numeric(auc(rb)), AUC_extension = as.numeric(auc(re)),
    delta_AUC = as.numeric(auc(re) - auc(rb)), z = as.numeric(test$statistic), p = as.numeric(test$p.value))
}, by = .(comparison, benchmark, extension)]
fwrite(delong, file.path(model_dir, "paired_delong_auc.csv"))

expected_models <- c("BasicClinical", "CAD_YinPanel", "CAD_YinPanel_YinScore", "CAD_YinPanel_YYScore",
                     "BasicClinical_CAD_YinPanel", "BasicClinical_CAD_YinPanel_YinScore",
                     "BasicClinical_CAD_YinPanel_YYScore")
design <- fread(file.path(model_dir, "model_design_contract.csv"))
pair_ok <- all(vapply(list(
  c("CAD_YinPanel_YinScore", "CAD_YinPanel_YYScore"),
  c("BasicClinical_CAD_YinPanel_YinScore", "BasicClinical_CAD_YinPanel_YYScore")
), function(pair) {
  a <- design[model_id == pair[[1L]]]; b <- design[model_id == pair[[2L]]]
  nrow(a) == 1L && nrow(b) == 1L && a$feature_n == b$feature_n &&
    identical(a$selected_protein_hash, b$selected_protein_hash)
}, logical(1)))
per_model_n <- pred[, .N, by = model_id]$N
qc <- rbindlist(list(
  data.table(check = "exact_model_ids", status = if (setequal(unique(pred$model_id), expected_models)) "PASS" else "FAIL",
             detail = paste(sort(unique(pred$model_id)), collapse = ";")),
  data.table(check = "same_holdout_n_per_model", status = if (length(unique(per_model_n)) == 1L) "PASS" else "FAIL",
             detail = paste(unique(per_model_n), collapse = ";")),
  data.table(check = "unique_eid_model", status = if (!anyDuplicated(pred[, .(eid, model_id)])) "PASS" else "FAIL",
             detail = sum(duplicated(pred[, .(eid, model_id)]))),
  data.table(check = "finite_predictions", status = if (all(is.finite(pred$prediction))) "PASS" else "FAIL",
             detail = sum(!is.finite(pred$prediction))),
  data.table(check = "predictions_in_0_1", status = if (all(pred$prediction >= 0 & pred$prediction <= 1)) "PASS" else "FAIL",
             detail = paste(range(pred$prediction), collapse = ",")),
  data.table(check = "matched_yin_yy_design", status = if (pair_ok) "PASS" else "FAIL", detail = pair_ok)
))
fwrite(qc, file.path(model_dir, "CODEX_QC.csv"))
if (any(qc$status == "FAIL")) stop("CAD Yu-style YYScore output QC failed.", call. = FALSE)
cat("PASS: hold-out metrics, paired DeLong comparisons, and QC written.\n")
