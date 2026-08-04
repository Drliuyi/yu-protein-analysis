suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(digest)
})

`%||%` <- function(x, y) if (is.null(x) || !length(x) || (length(x) == 1L && is.na(x))) y else x

yuy_now <- function() format(Sys.time(), "%Y-%m-%d %H:%M:%S")
yuy_bool <- function(x) isTRUE(x) || tolower(as.character(x %||% "false")) %in% c("1", "true", "yes", "y")
yuy_normalize_eid <- function(x) sub("\\.0$", "", trimws(as.character(x)))
yuy_norm_name <- function(x) gsub("^_|_$", "", gsub("[^a-z0-9]+", "_", tolower(trimws(as.character(x)))))

yuy_parse_cli <- function(args) {
  out <- list(); i <- 1L
  while (i <= length(args)) {
    token <- args[[i]]
    if (!startsWith(token, "--")) stop("Unexpected argument: ", token)
    token <- sub("^--", "", token)
    if (grepl("=", token, fixed = TRUE)) {
      bits <- strsplit(token, "=", fixed = TRUE)[[1]]
      key <- bits[[1]]; value <- paste(bits[-1], collapse = "=")
    } else {
      key <- token
      if (i < length(args) && !startsWith(args[[i + 1L]], "--")) { i <- i + 1L; value <- args[[i]] } else value <- TRUE
    }
    out[[gsub("-", "_", key, fixed = TRUE)]] <- value
    i <- i + 1L
  }
  out
}

yuy_abs_path <- function(path, dir0, script_dir = NULL) {
  path <- as.character(path %||% "")
  if (!nzchar(path)) return("")
  if (grepl("^([A-Za-z]:[/\\\\]|/)", path)) return(normalizePath(path, winslash = "/", mustWork = FALSE))
  root <- if (!is.null(script_dir) && startsWith(path, "config/")) script_dir else dir0
  normalizePath(file.path(root, path), winslash = "/", mustWork = FALSE)
}

yuy_init_config <- function(script_dir, cli) {
  cfg <- jsonlite::read_json(file.path(script_dir, "config", "defaults.json"), simplifyVector = TRUE)
  for (nm in names(cli)) cfg[[nm]] <- cli[[nm]]
  cfg$script_dir <- normalizePath(script_dir, winslash = "/", mustWork = TRUE)
  cfg$dir0 <- normalizePath(cfg$dir0 %||% getwd(), winslash = "/", mustWork = FALSE)
  cfg$mode <- tolower(as.character(cfg$mode %||% "help"))
  cfg$resume <- yuy_bool(cfg$resume %||% FALSE)
  cfg$force <- yuy_bool(cfg$force %||% FALSE)
  for (v in c("workers", "bootstrap_n", "split_seed", "inner_fold_seed", "inner_folds", "yys_min_cases_per_bin")) cfg[[v]] <- as.integer(cfg[[v]])
  cfg$phenotype_rds <- yuy_abs_path(cfg$phenotype_rds, cfg$dir0)
  cfg$raw_protein_file <- yuy_abs_path(cfg$raw_protein_file, cfg$dir0)
  cfg$panel_mapping_file <- yuy_abs_path(cfg$panel_mapping_file, cfg$dir0)
  cfg$official_panel_file <- yuy_abs_path(cfg$official_panel_file, cfg$dir0, cfg$script_dir)
  cfg$analysis_root <- yuy_abs_path(
    cfg$analysis_root %||% file.path(cfg$dir0, "analysis"), cfg$dir0
  )
  cfg$analysis_dir <- normalizePath(
    file.path(cfg$analysis_root, cfg$analysis_project), winslash = "/", mustWork = FALSE
  )
  dirs <- c(logs="00_logs", preflight="01_preflight", cohort="02_cohort", panel="03_panel", split="04_split", yys="05_yys", matrices="06_matrices", models="07_models", evaluation="08_evaluation", report="09_report", cache="90_cache")
  cfg$paths <- lapply(dirs, function(x) file.path(cfg$analysis_dir, x))
  for (p in cfg$paths) dir.create(p, recursive = TRUE, showWarnings = FALSE)
  cfg$paths$run_log <- file.path(cfg$paths$logs, "run.log")
  cfg
}

yuy_log <- function(cfg, ..., level = "INFO") {
  line <- sprintf("%s | %s | %s", yuy_now(), level, paste(..., collapse = ""))
  cat(line, "\n"); cat(line, "\n", file = cfg$paths$run_log, append = TRUE)
  invisible(line)
}

yuy_write_csv <- function(x, path) { dir.create(dirname(path), recursive=TRUE, showWarnings=FALSE); fwrite(as.data.table(x), path, na=""); invisible(path) }
yuy_write_json <- function(x, path) { dir.create(dirname(path), recursive=TRUE, showWarnings=FALSE); write_json(x, path, pretty=TRUE, auto_unbox=TRUE, null="null", na="null"); invisible(path) }
yuy_sha_file <- function(path) if (file.exists(path)) digest(path, algo="sha256", file=TRUE, serialize=FALSE) else NA_character_
yuy_sha_text <- function(x) digest(paste(as.character(x), collapse="\n"), algo="sha256", serialize=FALSE)

yuy_run_stage <- function(cfg, stage, fun) {
  done <- file.path(cfg$paths$logs, paste0(stage, ".done.json"))
  if (cfg$resume && file.exists(done) && !cfg$force) { yuy_log(cfg, "Resume: skip ", stage); return(invisible(NULL)) }
  started <- Sys.time(); yuy_log(cfg, "START ", stage)
  tryCatch({ fun(); yuy_write_json(list(stage=stage,status="PASS",started=format(started),ended=yuy_now(),elapsed_seconds=as.numeric(difftime(Sys.time(),started,units="secs"))),done); yuy_log(cfg,"DONE ",stage) }, error=function(e) { yuy_write_json(list(stage=stage,status="ERROR",message=conditionMessage(e),ended=yuy_now()),file.path(cfg$paths$logs,paste0(stage,".error.json"))); stop(e) })
}

yuy_as_date <- function(x) { if (inherits(x,"Date")) x else suppressWarnings(as.Date(x)) }
yuy_min_date <- function(dt, cols) {
  miss <- setdiff(cols,names(dt)); if(length(miss)) stop("Missing endpoint fields: ",paste(miss,collapse=", "))
  vals <- lapply(cols,function(v) as.numeric(yuy_as_date(dt[[v]])))
  z <- do.call(pmin,c(vals,list(na.rm=TRUE))); z[!is.finite(z)] <- NA_real_; as.Date(z,origin="1970-01-01")
}

yuy_rank_norm <- function(x, floor=.05) {
  out <- rep(NA_real_,length(x)); ok <- is.finite(x)
  if(sum(ok)==1L) out[ok] <- 1
  if(sum(ok)>1L) { r <- frank(x[ok],ties.method="average"); out[ok] <- floor+(1-floor)*(r-1)/(sum(ok)-1) }
  out
}

yuy_print_help <- function() {
  cat(paste0(
    "Yu/Chen-style CAD 257-protein benchmark + YYScore257\n\n",
    "Modes:\n",
    "  preflight  Validate sources, official 257 list, local header, packages and hashes.\n",
    "  prepare    Build baseline-CVD-free cohort, fixed 2/3-1/3 split, SCORE2 inputs and training-only YYScore257.\n",
    "  train      Fit five fixed LightGBM models with ten-fold derivation diagnostics.\n",
    "  evaluate   Hold-out AUC/metrics, paired DeLong and participant bootstrap.\n",
    "  report     Create source-locked summary tables and report.\n",
    "  all        Run all stages in order.\n\n",
    "Required inputs (defaults under D:/UKB_data):\n",
    "  phe/Rdata/all.rds\n  phe/raw/prot_full_unimputed.tsv\n  ppp/map.raw/olink_protein_map_3k_v1.tsv\n\n",
    "Important: no old FairK/ProtWAS/model results are accepted as inputs.\n"
  ))
}

yuy_session_snapshot <- function(cfg) {
  capture.output(sessionInfo(),file=file.path(cfg$paths$logs,"sessionInfo.txt"))
  capture.output(RNGkind(),file=file.path(cfg$paths$logs,"RNGkind.txt"))
}
