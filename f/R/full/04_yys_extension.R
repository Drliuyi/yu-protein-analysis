yur_rank_norm <- function(x, floor = 0.05) {
  out <- rep(NA_real_, length(x))
  ok <- is.finite(x)
  if (!any(ok)) return(out)
  ranks <- rank(x[ok], ties.method = "average")
  unit <- if (sum(ok) == 1L) 0.5 else (ranks - 1) / (sum(ok) - 1)
  out[ok] <- floor + (1 - floor) * unit
  out
}

yur_adjusted_contrast <- function(z_case, z_ref, clin_case, clin_ref) {
  z <- rbind(z_ref, z_case)
  group <- c(rep(0, nrow(z_ref)), rep(1, nrow(z_case)))
  design <- cbind(1, rbind(clin_ref, clin_case))
  group_residual <- qr.resid(qr(design), group)
  denominator <- sum(group_residual * group)
  if (!is.finite(denominator) || abs(denominator) < 1e-10) return(rep(NA_real_, ncol(z)))
  as.numeric(crossprod(group_residual, z) / denominator)
}

yur_yin_direction <- function(z, y, clinical) {
  fit <- glm(y ~ ., data = data.frame(y = y, clinical), family = binomial())
  probability <- pmin(1 - 1e-6, pmax(1e-6, fitted(fit)))
  residual <- y - probability
  score <- as.numeric(crossprod(residual, z))
  information <- colSums(sweep(z^2, 1, probability * (1 - probability), "*"))
  score / pmax(information, 1e-12)
}

yur_yys_clinical_matrix <- function(meta, training_medians = NULL) {
  variables <- c("age", "sex", "ethnicity_white", "smoking_current", "bmi", "sbp")
  missing <- setdiff(variables, names(meta))
  if (length(missing)) stop("YYScore metadata lacks: ", paste(missing, collapse = ", "))
  matrix <- as.matrix(meta[, ..variables])
  storage.mode(matrix) <- "double"
  if (is.null(training_medians)) {
    training_medians <- apply(matrix, 2, median, na.rm = TRUE)
  }
  for (j in seq_len(ncol(matrix))) matrix[!is.finite(matrix[, j]), j] <- training_medians[[j]]
  list(matrix = matrix, medians = training_medians)
}

yur_compute_abcd <- function(z_train, z_yang, train_meta, yang_meta, features, cfg) {
  clin_train <- yur_yys_clinical_matrix(train_meta)
  clin_yang <- yur_yys_clinical_matrix(yang_meta, clin_train$medians)
  yin <- yur_yin_direction(z_train, train_meta$event_cad, clin_train$matrix)
  overall <- yur_adjusted_contrast(z_yang, z_train, clin_yang$matrix, clin_train$matrix)

  breaks <- cfg$yys_bins_years
  labels <- paste0("bin_", head(breaks, -1), "_", tail(breaks, -1))
  bins <- cut(
    yang_meta$years_since_cad, breaks = breaks, right = FALSE,
    include.lowest = TRUE, labels = labels
  )
  delta_by_bin <- matrix(
    NA_real_, nrow = length(features), ncol = length(labels),
    dimnames = list(features, labels)
  )
  bin_n <- integer(length(labels))
  for (b in seq_along(labels)) {
    index <- which(bins == labels[[b]])
    bin_n[[b]] <- length(index)
    if (length(index) >= cfg$yys_min_cases_per_bin) {
      delta_by_bin[, b] <- yur_adjusted_contrast(
        z_yang[index, , drop = FALSE], z_train,
        clin_yang$matrix[index, , drop = FALSE], clin_train$matrix
      )
    }
  }
  if (sum(bin_n >= cfg$yys_min_cases_per_bin) < 2L) {
    stop("Fewer than two Yang time bins meet yys_min_cases_per_bin; ABCD breadth is not identifiable.")
  }

  floor <- cfg$yys_floor
  A <- yur_rank_norm(abs(overall), floor)
  strength <- abs(delta_by_bin)
  total_strength <- rowSums(strength, na.rm = TRUE)
  shares <- strength / pmax(total_strength, 1e-12)
  valid_bins <- rowSums(is.finite(delta_by_bin))
  effective_bins <- 1 / pmax(rowSums(shares^2, na.rm = TRUE), 1e-12)
  breadth_raw <- (effective_bins - 1) / pmax(valid_bins - 1, 1)
  breadth_raw[total_strength < 1e-12 | valid_bins < 2] <- NA_real_
  B <- floor + (1 - floor) * pmax(0, pmin(1, breadth_raw))

  bin_weights <- sqrt(pmax(bin_n, 1))
  bin_weights <- bin_weights / sum(bin_weights)
  abs_sum <- rowSums(sweep(abs(delta_by_bin), 2, bin_weights, "*"), na.rm = TRUE)
  signed_sum <- abs(rowSums(sweep(delta_by_bin, 2, bin_weights, "*"), na.rm = TRUE))
  direction_balance <- signed_sum / pmax(abs_sum, 1e-12)
  robust_mad <- apply(delta_by_bin, 1, function(x) median(abs(x - median(x, na.rm = TRUE)), na.rm = TRUE))
  robust_scale <- apply(abs(delta_by_bin), 1, median, na.rm = TRUE)
  epsilon <- max(median(robust_scale[is.finite(robust_scale)], na.rm = TRUE) * 0.1, 1e-8)
  magnitude_stability <- exp(-robust_mad / (robust_scale + epsilon))
  C <- floor + (1 - floor) * sqrt(pmax(0, direction_balance) * pmax(0, magnitude_stability))

  tau <- median(abs(overall), na.rm = TRUE)
  if (!is.finite(tau) || tau <= 0) tau <- 1e-6
  signed_alignment <- sign(yin) * overall
  D <- pmax(floor, pmin(1, 0.5 + 0.5 * signed_alignment / (abs(overall) + tau)))

  raw <- (A * B * C * D)^(1 / 4)
  yys <- yur_rank_norm(raw, floor)
  components <- data.table(
    feature_id = features, beta_yin = yin, delta_yang = overall,
    A = A, B = B, C = C, D = D, YYS_raw = raw, YYS = yys,
    sign_yang = sign(overall), weight = sign(overall) * yys,
    B_effective_bins = effective_bins, C_direction_balance = direction_balance,
    C_magnitude_stability = magnitude_stability, D_tau = tau
  )
  for (b in seq_along(labels)) components[[paste0("delta_", labels[[b]])]] <- delta_by_bin[, b]
  list(
    components = components,
    bin_counts = data.table(bin = labels, lower_year = head(breaks, -1), upper_year = tail(breaks, -1), n_yang = bin_n),
    clinical_medians = clin_train$medians
  )
}

yur_component_qc <- function(components, cfg) {
  q <- cfg$component_qc
  rows <- rbindlist(lapply(c("A", "B", "C", "D"), function(variable) {
    values <- components[[variable]]
    finite <- values[is.finite(values)]
    boundary <- if (length(finite)) {
      max(mean(abs(finite - cfg$yys_floor) < 1e-12), mean(abs(finite - 1) < 1e-12))
    } else 1
    data.table(
      component = variable, missing_fraction = mean(!is.finite(values)),
      sd = sd(finite), distinct_n = uniqueN(round(finite, 12)), boundary_fraction = boundary
    )
  }))
  rows[, status := fifelse(
    missing_fraction <= q$missing_fraction_max & sd >= q$sd_min &
      distinct_n >= q$distinct_min & boundary_fraction <= q$boundary_fraction_max,
    "PASS", "FAIL"
  )]
  correlation <- suppressWarnings(cor(
    components[, .(A, B, C, D)], method = "spearman", use = "pairwise.complete.obs"
  ))
  pairs <- as.data.table(as.table(correlation))
  setnames(pairs, c("component_1", "component_2", "spearman"))
  pairs <- pairs[component_1 < component_2]
  pairs[, status := fifelse(abs(spearman) <= q$pairwise_abs_spearman_max, "PASS", "FAIL")]
  list(component = rows, correlation = pairs, pass = all(rows$status == "PASS") && all(pairs$status == "PASS"))
}

yur_prepare_yys_extension <- function(cfg) {
  feature_file <- file.path(cfg$paths$selection, "final_cross_endpoint_protein_union.csv")
  train_file <- file.path(cfg$paths$cohort, "derivation_cohort.csv.gz")
  test_file <- file.path(cfg$paths$cohort, "test_cohort.csv.gz")
  yang_file <- file.path(cfg$paths$cohort, "yang_cad_auxiliary.csv.gz")
  required <- c(feature_file, train_file, test_file, yang_file)
  if (any(!file.exists(required))) stop("Run cohort and all-endpoint select first; missing: ", paste(required[!file.exists(required)], collapse = ", "))

  features <- unique(fread(feature_file)$feature_id)
  if (!length(features)) stop("Selected cross-endpoint protein union is empty.")
  train <- fread(train_file)
  test <- fread(test_file)
  yang <- fread(yang_file)
  if (!"event_cad" %in% names(train)) stop("Derivation cohort lacks event_cad.")
  if (nrow(yang) < 50L) stop("Too few prevalent CAD Yang cases: ", nrow(yang))

  header <- names(fread(cfg$raw_protein_file, nrows = 0, showProgress = FALSE))
  eid_col <- intersect(c("eid", "id", "f.eid", "participant_id"), header)[[1]]
  missing_features <- setdiff(features, header)
  if (length(missing_features)) stop("Selected proteins missing from raw table: ", paste(head(missing_features, 10L), collapse = ", "))
  raw <- fread(cfg$raw_protein_file, select = c(eid_col, features), nThread = cfg$workers, showProgress = TRUE)
  setnames(raw, eid_col, "eid")
  raw[, eid := yur_norm_eid(eid)]
  setkey(raw, eid)
  train[, eid := yur_norm_eid(eid)]; test[, eid := yur_norm_eid(eid)]; yang[, eid := yur_norm_eid(eid)]
  missing_eids <- setdiff(c(train$eid, test$eid, yang$eid), raw$eid)
  if (length(missing_eids)) stop("Raw protein input lacks ", length(unique(missing_eids)), " YYScore EIDs.")

  train_matrix <- as.matrix(raw[J(train$eid), ..features])
  test_matrix <- as.matrix(raw[J(test$eid), ..features])
  yang_matrix <- as.matrix(raw[J(yang$eid), ..features])
  colnames(train_matrix) <- colnames(test_matrix) <- colnames(yang_matrix) <- features
  training_missingness <- colMeans(is.na(train_matrix))
  if (any(training_missingness > cfg$protein_missingness_max)) {
    stop("Selected benchmark union contains proteins failing derivation missingness threshold; benchmark/YYS inputs must remain identical.")
  }
  medians <- apply(train_matrix, 2, median, na.rm = TRUE)
  standard_deviations <- apply(train_matrix, 2, sd, na.rm = TRUE)
  if (any(!is.finite(medians) | !is.finite(standard_deviations) | standard_deviations <= 0)) {
    stop("Invalid derivation median/SD for YYScore proteins.")
  }
  standardize <- function(matrix) {
    for (j in seq_len(ncol(matrix))) matrix[is.na(matrix[, j]), j] <- medians[[j]]
    sweep(sweep(matrix, 2, medians, "-"), 2, standard_deviations, "/")
  }
  z_train <- standardize(train_matrix)
  z_test <- standardize(test_matrix)
  z_yang <- standardize(yang_matrix)

  abcd <- yur_compute_abcd(z_train, z_yang, train, yang, features, cfg)
  qc <- yur_component_qc(abcd$components, cfg)
  yur_write_csv(abcd$components, file.path(cfg$paths$yys, "abcd_yys_components.csv"))
  yur_write_csv(abcd$bin_counts, file.path(cfg$paths$yys, "yang_bin_counts.csv"))
  yur_write_csv(qc$component, file.path(cfg$paths$yys, "abcd_component_qc.csv"))
  yur_write_csv(qc$correlation, file.path(cfg$paths$yys, "abcd_component_correlation_qc.csv"))
  if (!qc$pass) {
    stop("ABCD component QC failed before test prediction. No component may be removed after inspecting test results.")
  }

  weights <- abcd$components$weight
  raw_train_score <- as.numeric(z_train %*% weights)
  raw_test_score <- as.numeric(z_test %*% weights)
  raw_yang_score <- as.numeric(z_yang %*% weights)
  score_mean <- mean(raw_train_score)
  score_sd <- sd(raw_train_score)
  if (!is.finite(score_sd) || score_sd <= 0) stop("YYScore derivation SD is invalid.")
  score <- function(x) (x - score_mean) / score_sd
  yur_write_csv(data.table(eid = train$eid, YYScore = score(raw_train_score)), file.path(cfg$paths$yys, "yys_score_derivation.csv"))
  yur_write_csv(data.table(eid = test$eid, YYScore = score(raw_test_score)), file.path(cfg$paths$yys, "yys_score_test.csv"))
  yur_write_csv(data.table(eid = yang$eid, YYScore = score(raw_yang_score)), file.path(cfg$paths$yys, "yys_score_yang.csv"))
  yur_write_csv(data.table(feature_id = features, training_missing_rate = training_missingness, median = medians, sd = standard_deviations), file.path(cfg$paths$yys, "training_protein_transform.csv"))
  yur_write_json(list(
    status = "PASS", outcome = "cad", protein_n = length(features), protein_hash = yur_sha_text(features),
    derivation_n = nrow(train), derivation_events = sum(train$event_cad), test_n = nrow(test),
    yang_n = nrow(yang), yys_floor = cfg$yys_floor, yys_bins_years = cfg$yys_bins_years,
    score_mean_derivation = score_mean, score_sd_derivation = score_sd,
    component_qc_pass = TRUE,
    formula = "YYS_raw=(A*B*C*D)^(1/4); YYS=0.05+0.95*rank_norm(YYS_raw); weight=sign(delta_Yang)*YYS; YYScore=sum(weight*Z)",
    information_boundary = "ABCD, transforms and YYScore parameters use derivation plus prevalent-CAD auxiliary data; hold-out outcomes are never used."
  ), file.path(cfg$paths$yys, "yys_manifest.json"))
  saveRDS(list(
    features = features, protein_median = medians, protein_sd = standard_deviations,
    clinical_medians = abcd$clinical_medians, score_mean = score_mean, score_sd = score_sd,
    weights = weights
  ), file.path(cfg$paths$cache, "yys_training_parameters.rds"), compress = TRUE)
}
