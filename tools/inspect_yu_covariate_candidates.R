args <- commandArgs(trailingOnly = TRUE)
phenotype_file <- if (length(args)) args[[1]] else "D:/UKB_data/phe/Rdata/all.rds"
output_file <- if (length(args) >= 2L) args[[2]] else ""

if (!file.exists(phenotype_file)) stop("Phenotype file not found: ", phenotype_file)
x <- readRDS(phenotype_file)
if (any(vapply(x, inherits, logical(1), what = "integer64"))) {
  if (!requireNamespace("bit64", quietly = TRUE)) stop("Package bit64 is required to audit integer64 fields.")
  loadNamespace("bit64")
}
patterns <- c(
  fasting = "fast|6142|74[.]0|74$",
  season = "season|month|date_attend|assessment_date|blood.*date|collection.*date",
  protein_lag = "lag|delay|sample|sampling|assay|protein.*date|collection.*date|30900|30901|30902",
  technical = "plate|batch|well|array"
)

rows <- lapply(names(patterns), function(group) {
  hits <- grep(patterns[[group]], names(x), value = TRUE, ignore.case = TRUE)
  if (!length(hits)) return(NULL)
  do.call(rbind, lapply(hits, function(variable) {
    value <- x[[variable]]
    if (inherits(value, "integer64")) {
      observed <- !is.na(value)
      display <- format(value[observed], scientific = FALSE, trim = TRUE)
      finite_n <- sum(observed)
      examples <- unique(display)
      unique_n <- length(unique(display))
    } else {
      observed <- !is.na(value)
      finite_n <- if (is.numeric(value)) sum(is.finite(value)) else sum(observed)
      examples <- unique(as.character(value[observed]))
      unique_n <- length(unique(value[observed]))
    }
    data.frame(
      group = group,
      variable = variable,
      class = paste(class(value), collapse = ";"),
      n = length(value),
      observed_n = finite_n,
      missing_rate = 1 - finite_n / length(value),
      unique_n = unique_n,
      examples = paste(utils::head(examples, 5L), collapse = " | "),
      stringsAsFactors = FALSE
    )
  }))
})
audit <- do.call(rbind, rows)
if (is.null(audit)) audit <- data.frame()

if (nzchar(output_file)) {
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(audit, output_file, na = "")
}
print(audit, row.names = FALSE)
