#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_dir <- if (length(file_arg)) dirname(normalizePath(sub("^--file=", "", file_arg[[1]]))) else getwd()

source(file.path(script_dir, "R", "00_utils.R"))
source(file.path(script_dir, "R", "01_preflight.R"))
source(file.path(script_dir, "R", "02_prepare_yys.R"))
source(file.path(script_dir, "R", "03_evaluate_report.R"))

cli <- yuy_parse_cli(commandArgs(trailingOnly = TRUE))
cfg <- yuy_init_config(script_dir, cli)

if (cfg$mode == "help") {
  yuy_print_help()
  quit(save = "no", status = 0)
}

yuy_session_snapshot(cfg)
yuy_log(cfg, "Mode=", cfg$mode)

run <- function(stage, fun) yuy_run_stage(cfg, stage, fun)
if (cfg$mode %in% c("preflight", "all")) run("preflight", function() yuy_preflight(cfg))
if (cfg$mode %in% c("prepare", "all")) run("prepare", function() yuy_prepare(cfg))
if (cfg$mode %in% c("evaluate", "all")) run("evaluate", function() yuy_evaluate(cfg))
if (cfg$mode %in% c("report", "all")) run("report", function() yuy_report(cfg))
if (cfg$mode == "train") {
  stop("Mode=train is dispatched by tools/run_yu_yys_windows.ps1 to Python.", call. = FALSE)
}
if (!cfg$mode %in% c("preflight", "prepare", "evaluate", "report", "all")) {
  stop("Unsupported mode: ", cfg$mode, call. = FALSE)
}
