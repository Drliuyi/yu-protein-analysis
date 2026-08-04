yuy_preflight <- function(cfg) {
  required <- c("data.table","jsonlite","digest","pROC")
  pkg <- data.table(package=required,available=vapply(required,requireNamespace,logical(1),quietly=TRUE))
  yuy_write_csv(pkg,file.path(cfg$paths$preflight,"r_package_check.csv"))
  if(any(!pkg$available)) stop("Missing R packages: ",paste(pkg[!available,package],collapse=", "))
  inputs <- data.table(role=c("phenotype","raw_protein","local_mapping","official_257"),path=c(cfg$phenotype_rds,cfg$raw_protein_file,cfg$panel_mapping_file,cfg$official_panel_file))
  inputs[,exists:=file.exists(path)]
  inputs[,bytes:=fifelse(exists,file.info(path)$size,NA_real_)]
  if(any(!inputs$exists)) stop("Missing inputs: ",paste(inputs[!exists,path],collapse=", "))
  inputs[,sha256:=vapply(path,yuy_sha_file,character(1))]
  yuy_write_csv(inputs,file.path(cfg$paths$preflight,"input_manifest.csv"))

  official <- fread(cfg$official_panel_file)
  if(nrow(official)!=257L || uniqueN(official$protein)!=257L) stop("Official CAD panel must contain exactly 257 unique proteins.")
  header <- names(fread(cfg$raw_protein_file,nrows=0,showProgress=FALSE))
  eid_hit <- intersect(c("eid","id","f.eid","participant_id"),header)
  if(!length(eid_hit)) stop("No EID in raw protein header.")
  feature_header <- setdiff(header,eid_hit[[1]])
  lookup <- data.table(raw_feature=feature_header,norm=yuy_norm_name(feature_header))
  official[,norm:=yuy_norm_name(local_feature)]
  map <- merge(official,lookup,by="norm",all.x=TRUE,allow.cartesian=TRUE)
  map[,raw_match_n:=.N,by=protein]
  map[,mapping_status:=fifelse(is.na(raw_feature),"MISSING_RAW",fifelse(raw_match_n==1L,"PASS_EXACT_VARIABLE","AMBIGUOUS_RAW"))]

  local_map <- fread(cfg$panel_mapping_file)
  symbol_col <- intersect(c("HGNC.symbol","Assay","assay","gene_symbol","symbol"),names(local_map))
  if(length(symbol_col)) {
    lm <- local_map[,.(local_mapping_rows=.N,local_panels=paste(sort(unique(as.character(Panel))),collapse=";"),local_olink_ids=paste(sort(unique(as.character(OlinkID))),collapse=";")),by=.(protein=toupper(get(symbol_col[[1]])))]
    map <- merge(map,lm,by="protein",all.x=TRUE)
  }
  map[protein %in% c("IL6","TNF"),mapping_status:="PASS_COLLAPSED_MULTI_ASSAY_LIMITATION"]
  yuy_write_csv(map,file.path(cfg$paths$preflight,"official_257_local_mapping.csv"))
  status <- data.table(
    check=c("official_unique_257","all_raw_variables_found","il6_tnf_limitation_declared","raw_panel_not_preimputed"),
    status=c("PASS",ifelse(any(is.na(map$raw_feature)),"FAIL","PASS"),"PASS",ifelse(any(grepl("unimputed",tolower(cfg$raw_protein_file))),"PASS","REVIEW")),
    detail=c("257 unique proteins from Table S12",paste(sum(is.na(map$raw_feature)),"missing raw variables"),"Local raw table contains one collapsed feature for each; exact source assay cannot be reconstructed",cfg$raw_protein_file)
  )
  yuy_write_csv(status,file.path(cfg$paths$preflight,"preflight_status.csv"))
  if(any(status$status=="FAIL")) stop("Preflight failed. See preflight_status.csv")
  yuy_write_json(list(status="PASS",official_proteins=257,raw_protein_columns=length(feature_header),followup_cutoff=cfg$followup_cutoff,split_seed=cfg$split_seed,limitations=c("IL6 collapsed multi-assay","TNF collapsed multi-assay")),file.path(cfg$paths$preflight,"preflight_summary.json"))
  invisible(status)
}
