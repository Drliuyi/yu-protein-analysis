#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(data.table))

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
required <- c("prot_rds", "input_dir", "cache_dir")
missing <- required[!nzchar(vapply(required, function(x) as.character(opt[[x]] %||% ""), character(1)))]
if (length(missing)) stop("Missing arguments: ", paste(missing, collapse = ", "), call. = FALSE)
dir.create(opt$cache_dir, recursive = TRUE, showWarnings = FALSE)

meta <- fread(file.path(opt$input_dir, "target_metadata.csv.gz"), colClasses = list(character = "eid"))
order_dt <- fread(file.path(opt$input_dir, "protein_order.csv"))
proteins <- as.character(order_dt$protein)
if (nrow(meta) != 37127L || sum(meta$event) != 3442L || length(proteins) != 2910L) {
  stop("Frozen input contract failed before matrix preparation.", call. = FALSE)
}

clinical_vars <- c("age", "sex", "smoking", "sbp", "bp_treatment", "diabetes",
                   "total_cholesterol", "hdl")
missing_clinical <- setdiff(clinical_vars, names(meta))
if (length(missing_clinical)) {
  stop("Target metadata is missing Basic clinical variables: ",
       paste(missing_clinical, collapse = ", "), call. = FALSE)
}

cat("Loading WinPC protein RDS: ", opt$prot_rds, "\n", sep = "")
prot <- as.data.table(readRDS(opt$prot_rds))
eid_col <- intersect(c("eid", "id", "f.eid", "participant_id"), names(prot))[[1L]]
setnames(prot, eid_col, "eid")
prot[, eid := sub("\\.0$", "", trimws(as.character(eid)))]
if (anyDuplicated(prot$eid)) stop("Duplicate EIDs in prot.rds.", call. = FALSE)
missing_proteins <- setdiff(proteins, names(prot))
if (length(missing_proteins)) stop("prot.rds missing proteins: ", paste(head(missing_proteins, 20L), collapse = ", "), call. = FALSE)

idx <- match(meta$eid, prot$eid)
if (anyNA(idx)) stop("Target EIDs absent from prot.rds: ", sum(is.na(idx)), call. = FALSE)
X <- as.matrix(prot[idx, ..proteins])
storage.mode(X) <- "double"
missing_cells <- sum(!is.finite(X))
if (missing_cells) stop("Frozen prot.rds matrix contains non-finite cells: ", missing_cells, call. = FALSE)

meta <- meta[match(prot$eid[idx], eid)]
if (anyNA(meta$eid)) stop("Participant order failed after protein alignment.", call. = FALSE)

matrix_file <- file.path(opt$cache_dir, "protein_matrix_37127x2910_float32.bin")
con <- file(matrix_file, open = "wb")
on.exit(close(con), add = TRUE)
writeBin(as.numeric(t(X)), con, size = 4L, endian = "little")
close(con); on.exit(NULL, add = FALSE)
fwrite(meta, file.path(opt$cache_dir, "participants.csv.gz"))
fwrite(order_dt, file.path(opt$cache_dir, "protein_order.csv"))

expected_bytes <- as.double(nrow(X)) * as.double(ncol(X)) * 4
actual_bytes <- file.info(matrix_file)$size
if (actual_bytes != expected_bytes) stop("Binary matrix size mismatch.", call. = FALSE)
manifest <- data.table(
  item = c("participant_n", "event_n", "protein_n", "matrix_rows", "matrix_cols", "matrix_dtype",
           "matrix_order", "matrix_bytes", "protein_rds_md5", "participants_md5"),
  value = c(nrow(meta), sum(meta$event), length(proteins), nrow(X), ncol(X), "float32-little-endian",
            "C-row-major", actual_bytes, unname(tools::md5sum(opt$prot_rds)),
            unname(tools::md5sum(file.path(opt$cache_dir, "participants.csv.gz"))))
)
fwrite(manifest, file.path(opt$cache_dir, "matrix_manifest.csv"))
cat("PASS: matrix cache written to ", opt$cache_dir, "\n", sep = "")
