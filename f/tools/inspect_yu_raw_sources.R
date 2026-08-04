args <- commandArgs(trailingOnly = TRUE)
files <- if (length(args)) args else c(
  "D:/data/ukb/phe/pheno.tsv.gz",
  "D:/data/ukb/phe/prot.tab.gz",
  "D:/data/ukb/phe/raw/prot_full_unimputed.tsv"
)

patterns <- c(
  "^eid$", "^p74_i0$", "^p53_i0$", "^p3090[0-3]_i0$", "fast", "season", "collect",
  "sampl", "assay", "date", "plate", "batch", "lag", "delay", "protein"
)

for (path in files) {
  cat("\n=== ", path, " ===\n", sep = "")
  if (!file.exists(path)) {
    cat("MISSING\n")
    next
  }
  con <- if (grepl("\\.gz$", path, ignore.case = TRUE)) gzfile(path, "rt") else file(path, "rt")
  header <- readLines(con, n = 1L, warn = FALSE)
  close(con)
  names_available <- strsplit(header, "\t", fixed = TRUE)[[1L]]
  hits <- unique(unlist(lapply(patterns, function(pattern) {
    grep(pattern, names_available, value = TRUE, ignore.case = TRUE)
  })))
  cat("columns=", length(names_available), "\n", sep = "")
  cat(paste(hits, collapse = "\n"), "\n", sep = "")

  exact <- intersect(c("eid", "p53_i0", "p74_i0", "p30900_i0", "p30901_i0", "p30902_i0", "p30903_i0"), names_available)
  if (length(exact) && grepl("pheno\\.tsv\\.gz$", path, ignore.case = TRUE) && requireNamespace("data.table", quietly = TRUE)) {
    sample <- data.table::fread(path, select = exact, nrows = 1000L, showProgress = FALSE)
    cat("-- first-1000 exact-field audit --\n")
    for (field in exact) {
      values <- sample[[field]]
      examples <- unique(as.character(values[!is.na(values) & nzchar(as.character(values))]))
      cat(field, ": nonmissing=", sum(!is.na(values)), "; examples=", paste(head(examples, 5L), collapse = "|"), "\n", sep = "")
    }
  }
}
