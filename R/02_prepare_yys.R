yuy_sex_binary <- function(x) {
  z <- tolower(trimws(as.character(x))); out <- rep(NA_real_,length(z))
  out[z %in% c("female","f","woman","0")] <- 0
  out[z %in% c("male","m","man","1")] <- 1
  out
}

yuy_current_smoker <- function(x) {
  z <- tolower(trimws(as.character(x))); out <- rep(NA_real_,length(z))
  out[grepl("current",z)] <- 1
  out[grepl("never|previous|former",z)] <- 0
  suppressWarnings({ num <- as.numeric(z); out[is.na(out)&num %in% c(0,1)] <- num[is.na(out)&num %in% c(0,1)] })
  out
}

yuy_mode <- function(x) {
  z <- x[!is.na(x)]; if(!length(z)) return(NA_real_)
  as.numeric(names(sort(table(z),decreasing=TRUE)[1]))
}

yuy_score2_vector <- function(age,sex,smoker,sbp,diabetes,tc,hdl) {
  out <- rep(NA_real_,length(age))
  for(i in seq_along(out)) {
    male <- sex[[i]]==1; a <- age[[i]]; sm <- smoker[[i]]; s <- sbp[[i]]; dm <- diabetes[[i]]; t <- tc[[i]]; h <- hdl[[i]]
    if(any(!is.finite(c(a,sex[[i]],sm,s,dm,t,h)))) next
    if(a < 70) {
      if(male) {
        lp <- .3742*(a-60)/5 + .6012*sm + .2777*(s-120)/20 + .6457*dm + .1458*(t-6) - .2698*(h-1.3)/.5 - .0755*(a-60)/5*sm - .0255*(a-60)/5*(s-120)/20 - .0281*(a-60)/5*(t-6) + .0426*(a-60)/5*(h-1.3)/.5 - .0983*(a-60)/5*dm
        base <- 1-.9605^exp(lp); sc1 <- -.5699; sc2 <- .7476
      } else {
        lp <- .4648*(a-60)/5 + .7744*sm + .3131*(s-120)/20 + .8096*dm + .1002*(t-6) - .2606*(h-1.3)/.5 - .1088*(a-60)/5*sm - .0277*(a-60)/5*(s-120)/20 - .0226*(a-60)/5*(t-6) + .0613*(a-60)/5*(h-1.3)/.5 - .1272*(a-60)/5*dm
        base <- 1-.9776^exp(lp); sc1 <- -.7380; sc2 <- .7019
      }
    } else {
      if(male) {
        lp <- .0634*(a-73)+.4245*dm+.3524*sm+.0094*(s-150)+.0850*(t-6)-.3564*(h-1.4)-.0174*(a-73)*dm-.0247*(a-73)*sm-.0005*(a-73)*(s-150)+.0073*(a-73)*(t-6)+.0091*(a-73)*(h-1.4)
        base <- 1-.7576^exp(lp-.0929); sc1 <- -.34; sc2 <- 1.19
      } else {
        lp <- .0789*(a-73)+.6010*dm+.4921*sm+.0102*(s-150)+.0605*(t-6)-.3040*(h-1.4)-.0107*(a-73)*dm-.0255*(a-73)*sm-.0004*(a-73)*(s-150)+.0067*(a-73)*(t-6)+.0094*(a-73)*(h-1.4)
        base <- 1-.8082^exp(lp-.229); sc1 <- -.52; sc2 <- 1.01
      }
    }
    out[[i]] <- 1-exp(-exp(sc1+sc2*log(-log(1-base))))
  }
  pmin(1,pmax(0,out))
}

yuy_prepare_score2 <- function(train,test,yang) {
  cont <- c("total_cholesterol","hdl")
  params <- list()
  for(v in cont) { params[[v]] <- median(train[[v]],na.rm=TRUE); train[is.na(get(v)),(v):=params[[v]]]; test[is.na(get(v)),(v):=params[[v]]]; yang[is.na(get(v)),(v):=params[[v]]] }
  for(v in c("smoking_current","diabetes")) { params[[v]] <- yuy_mode(train[[v]]); train[is.na(get(v)),(v):=params[[v]]]; test[is.na(get(v)),(v):=params[[v]]]; yang[is.na(get(v)),(v):=params[[v]]] }
  for(v in "sbp") {
    sex_med <- train[,.(value=median(get(v),na.rm=TRUE)),by=sex]
    params[[paste0(v,"_by_sex")]] <- split(sex_med$value,sex_med$sex)
    for(d in list(train,test,yang)) for(sx in c(0,1)) d[is.na(get(v))&sex==sx,(v):=sex_med[sex==sx,value]]
  }
  for(d in list(train,test,yang)) d[,score2_raw:=yuy_score2_vector(age,sex,smoking_current,sbp,diabetes,total_cholesterol,hdl)]
  list(train=train,test=test,yang=yang,params=params)
}

yuy_adjusted_contrast <- function(z_case,z_ref,clin_case,clin_ref) {
  z <- rbind(z_ref,z_case); g <- c(rep(0,nrow(z_ref)),rep(1,nrow(z_case)))
  x <- cbind(1,rbind(clin_ref,clin_case)); qr_x <- qr(x); gr <- qr.resid(qr_x,g); den <- sum(gr*g)
  if(!is.finite(den)||abs(den)<1e-10) return(rep(NA_real_,ncol(z)))
  as.numeric(crossprod(gr,z)/den)
}

yuy_yin_direction <- function(z,y,clin) {
  fit <- glm(y~.,data=data.frame(y=y,clin),family=binomial()); p <- pmin(1-1e-6,pmax(1e-6,fitted(fit))); r <- y-p
  score <- as.numeric(crossprod(r,z)); info <- colSums(sweep(z^2,1,p*(1-p),"*")); score/pmax(info,1e-12)
}

yuy_compute_abcd <- function(z_train,z_yang,train_meta,yang_meta,features,cfg) {
  clin_vars <- c("age","sex","race_white","smoking_current","bmi","sbp")
  clin_train <- as.matrix(train_meta[,..clin_vars]); clin_yang <- as.matrix(yang_meta[,..clin_vars])
  for(j in seq_len(ncol(clin_train))) {
    med <- median(clin_train[,j],na.rm=TRUE); clin_train[is.na(clin_train[,j]),j] <- med; clin_yang[is.na(clin_yang[,j]),j] <- med
  }
  yin <- yuy_yin_direction(z_train,train_meta$incident_cad,clin_train)
  overall <- yuy_adjusted_contrast(z_yang,z_train,clin_yang,clin_train)
  br <- as.numeric(cfg$yys_bins_years); labels <- paste0("bin_",head(br,-1),"_",tail(br,-1)); bins <- cut(yang_meta$years_since_cad,breaks=br,right=FALSE,include.lowest=TRUE,labels=labels)
  db <- matrix(NA_real_,nrow=length(features),ncol=length(labels),dimnames=list(features,labels)); bn <- integer(length(labels))
  for(b in seq_along(labels)) { idx <- which(bins==labels[[b]]); bn[[b]] <- length(idx); if(length(idx)>=cfg$yys_min_cases_per_bin) db[,b] <- yuy_adjusted_contrast(z_yang[idx,,drop=FALSE],z_train,clin_yang[idx,,drop=FALSE],clin_train) }
  floor <- as.numeric(cfg$yys_floor); A <- yuy_rank_norm(abs(overall),floor)
  strength <- abs(db); ss <- rowSums(strength,na.rm=TRUE); share <- strength/pmax(ss,1e-12); vm <- rowSums(is.finite(db)); inv <- 1/pmax(rowSums(share^2,na.rm=TRUE),1e-12)
  braw <- (inv-1)/pmax(vm-1,1); braw[ss<1e-12|vm<2] <- NA_real_; B <- floor+(1-floor)*pmax(0,pmin(1,braw))
  wb <- sqrt(pmax(bn,1)); wb <- wb/sum(wb); abs_sum <- rowSums(sweep(abs(db),2,wb,"*"),na.rm=TRUE); signed_sum <- abs(rowSums(sweep(db,2,wb,"*"),na.rm=TRUE)); bal <- signed_sum/pmax(abs_sum,1e-12)
  rmad <- apply(db,1,function(x) median(abs(x-median(x,na.rm=TRUE)),na.rm=TRUE)); rscale <- apply(abs(db),1,median,na.rm=TRUE); eps <- max(median(rscale[is.finite(rscale)],na.rm=TRUE)*.1,1e-8); stab <- exp(-rmad/(rscale+eps)); C <- floor+(1-floor)*sqrt(pmax(0,bal)*pmax(0,stab))
  tau <- median(abs(overall),na.rm=TRUE); if(!is.finite(tau)||tau<=0) tau <- 1e-6; signed <- sign(yin)*overall; D <- pmax(floor,pmin(1,.5+.5*signed/(abs(overall)+tau)))
  raw <- (A*B*C*D)^(1/4); yys <- yuy_rank_norm(raw,floor)
  comp <- data.table(feature_id=features,beta_yin=yin,delta_yang=overall,A=A,B=B,C=C,D=D,YYS_raw=raw,YYS=yys,sign_yang=sign(overall),weight=sign(overall)*yys,B_effective_bins=inv,C_direction_balance=bal,C_magnitude_stability=stab,D_tau=tau)
  for(b in seq_along(labels)) comp[[paste0("delta_",labels[[b]])]] <- db[,b]
  list(components=comp,bin_counts=data.table(bin=labels,n_yang=bn))
}

yuy_component_qc <- function(x,cfg) {
  q <- cfg$component_qc
  rows <- rbindlist(lapply(c("A","B","C","D"),function(v) { z<-x[[v]]; f<-z[is.finite(z)]; boundary<-if(length(f)) max(mean(abs(f-cfg$yys_floor)<1e-12),mean(abs(f-1)<1e-12)) else 1; data.table(component=v,missing_fraction=mean(!is.finite(z)),sd=sd(f),distinct_n=uniqueN(round(f,12)),boundary_fraction=boundary) }))
  rows[,status:=fifelse(missing_fraction<=q$missing_fraction_max&sd>=q$sd_min&distinct_n>=q$distinct_min&boundary_fraction<=q$boundary_fraction_max,"PASS","FAIL")]
  cm <- suppressWarnings(cor(x[,.(A,B,C,D)],method="spearman",use="pairwise.complete.obs")); pairs <- as.data.table(as.table(cm)); setnames(pairs,c("component_1","component_2","spearman")); pairs <- pairs[component_1<component_2]; pairs[,status:=fifelse(abs(spearman)<=q$pairwise_abs_spearman_max,"PASS","FAIL")]
  list(component=rows,correlation=pairs,pass=all(rows$status=="PASS")&&all(pairs$status=="PASS"))
}

yuy_prepare <- function(cfg) {
  premap <- file.path(cfg$paths$preflight,"official_257_local_mapping.csv")
  if(!file.exists(premap)) stop("Run preflight first.")
  map <- fread(premap); if(any(is.na(map$raw_feature))) stop("Official proteins missing from raw data.")
  map <- unique(map[,.(protein,rank,uniprot,panel,raw_feature,mapping_status)])
  if(nrow(map)!=257L) stop("Expected 257 unique mapped features; found ",nrow(map))
  raw <- fread(cfg$raw_protein_file,select=c("eid",map$raw_feature),na.strings=c("","NA","NaN"),showProgress=TRUE,nThread=cfg$workers)
  raw[,eid:=yuy_normalize_eid(eid)]
  ph <- as.data.table(readRDS(cfg$phenotype_rds)); eidcol <- intersect(c("eid","id","f.eid"),names(ph))[[1]]; if(eidcol!="eid") setnames(ph,eidcol,"eid"); ph[,eid:=yuy_normalize_eid(eid)]
  sexcol <- if("sex.b"%in%names(ph)) "sex.b" else if("sex"%in%names(ph)) "sex" else stop("Missing sex")
  date_fields <- c(cmyo="fod_ref_cvd_cmyo",cad="fod_ref_cvd_cad",hf="fod_ref_cvd_hfail",af="fod_ref_cvd_afib",as="fod_ref_cvd_aosten",abaneu="fod_ref_cvd_abaneu",thaneu="fod_ref_cvd_thaneu",stroke_i="fod_ref_cvd_stroke_i",tia="fod_ref_cvd_tia",ich="fod_ref_cvd_stroke_ih",sah="fod_ref_cvd_stroke_sh",dvt="fod_ref_cvd_dvt",pe="fod_ref_cvd_pe",pad="fod_ref_cvd_pad")
  req <- c("date_attend","fod_icd10_cvd_cad","fod_icd9_cvd_cad","fod_opcs4_mi","age","ethnic.c","smoking","bmi","sbp","total_cholesterol","hdl","diabetes",sexcol,unname(date_fields))
  miss <- setdiff(req,names(ph)); if(length(miss)) stop("Phenotype fields missing: ",paste(miss,collapse=", "))
  x <- copy(ph[,c("eid",req),with=FALSE]); setnames(x,sexcol,"sex_source")
  for(v in c("date_attend","fod_icd10_cvd_cad","fod_icd9_cvd_cad","fod_opcs4_mi",unname(date_fields))) x[[v]] <- yuy_as_date(x[[v]])
  x[,cad_date:=yuy_min_date(.SD,c("fod_icd10_cvd_cad","fod_icd9_cvd_cad","fod_opcs4_mi"))]
  x[,`:=`(sex=yuy_sex_binary(sex_source),race_white=fifelse(is.na(ethnic.c),NA_real_,as.numeric(as.character(ethnic.c)=="White")),smoking_current=yuy_current_smoker(smoking),diabetes=as.numeric(diabetes))]
  x <- x[eid%in%raw$eid & !is.na(date_attend) & !is.na(sex)]
  for(nm in names(date_fields)) x[[paste0("prev_",nm)]] <- !is.na(x[[date_fields[[nm]]]]) & x[[date_fields[[nm]]]]<=x$date_attend
  x[,prev_cad:=(!is.na(cad_date)&cad_date<=date_attend)|prev_cad]
  prev_cols <- paste0("prev_",names(date_fields)); x[,any_baseline_cvd:=rowSums(as.matrix(.SD),na.rm=TRUE)>0,.SDcols=prev_cols]
  x[,incident_cad:=as.integer(!is.na(cad_date)&cad_date>date_attend&cad_date<=as.Date(cfg$followup_cutoff))]
  incident <- x[any_baseline_cvd == FALSE]
  other_prev <- setdiff(prev_cols,"prev_cad")
  x[,other_baseline_cvd:=rowSums(as.matrix(.SD),na.rm=TRUE)>0,.SDcols=other_prev]
  yang <- x[prev_cad == TRUE & other_baseline_cvd == FALSE]
  yang[,years_since_cad:=as.numeric(date_attend-cad_date)/365.25]
  set.seed(cfg$split_seed); ids <- sample(incident$eid); ntr <- floor(length(ids)*cfg$train_fraction); train_ids <- ids[seq_len(ntr)]; test_ids <- ids[-seq_len(ntr)]
  set.seed(cfg$inner_fold_seed); folds <- sample(rep(seq_len(cfg$inner_folds),length.out=length(train_ids))); fold_dt <- data.table(eid=train_ids,foldid=folds)
  train_meta <- incident[match(train_ids,eid)]; test_meta <- incident[match(test_ids,eid)]
  sc <- yuy_prepare_score2(copy(train_meta),copy(test_meta),copy(yang)); train_meta<-sc$train; test_meta<-sc$test; yang<-sc$yang
  yuy_write_csv(data.table(step=c("protein_and_required_baseline","exclude_any_14_baseline_CVD","derivation","holdout","yang_auxiliary"),n=c(nrow(x),nrow(incident),nrow(train_meta),nrow(test_meta),nrow(yang))),file.path(cfg$paths$cohort,"cohort_flow.csv"))
  yuy_write_csv(train_meta[,.(eid,incident_cad,date_attend,cad_date,score2_raw)],file.path(cfg$paths$split,"derivation_eid.csv")); yuy_write_csv(test_meta[,.(eid,incident_cad,date_attend,cad_date,score2_raw)],file.path(cfg$paths$split,"test_eid.csv")); yuy_write_csv(fold_dt,file.path(cfg$paths$split,"foldid.csv")); yuy_write_csv(yang[,.(eid,date_attend,cad_date,years_since_cad)],file.path(cfg$paths$cohort,"yang_auxiliary.csv"))
  writeLines(yuy_sha_text(c(sort(train_ids),"TEST",sort(test_ids))),file.path(cfg$paths$split,"split_hash.txt")); writeLines(yuy_sha_text(paste(fold_dt$eid,fold_dt$foldid,sep=":")),file.path(cfg$paths$split,"foldid_hash.txt"))

  setkey(raw,eid); features <- map$raw_feature
  ptrain <- as.matrix(raw[J(train_ids),..features]); ptest <- as.matrix(raw[J(test_ids),..features]); pyang <- as.matrix(raw[J(yang$eid),..features]); colnames(ptrain)<-colnames(ptest)<-colnames(pyang)<-features
  missing <- colMeans(is.na(ptrain)); panel_qc <- data.table(feature_id=map$raw_feature,protein=map$protein,rank=map$rank,training_missing_rate=missing,keep=missing<=cfg$protein_missingness_max)
  yuy_write_csv(panel_qc,file.path(cfg$paths$panel,"yu_257_training_missingness_qc.csv")); if(any(!panel_qc$keep)) stop("Published 257 panel has training missingness >30%; review panel QC before model fitting.")
  med <- apply(ptrain,2,median,na.rm=TRUE); sdev <- apply(ptrain,2,sd,na.rm=TRUE); if(any(!is.finite(med)|!is.finite(sdev)|sdev<=0)) stop("Invalid training protein median/SD")
  zfun <- function(m) { for(j in seq_len(ncol(m))) m[is.na(m[,j]),j] <- med[[j]]; sweep(sweep(m,2,med,"-"),2,sdev,"/") }
  ztrain<-zfun(ptrain); ztest<-zfun(ptest); zyang<-zfun(pyang)
  abcd <- yuy_compute_abcd(ztrain,zyang,train_meta,yang,map$raw_feature,cfg); qc <- yuy_component_qc(abcd$components,cfg)
  yuy_write_csv(abcd$components,file.path(cfg$paths$yys,"abcd_yys_components.csv")); yuy_write_csv(abcd$bin_counts,file.path(cfg$paths$yys,"yang_bin_counts.csv")); yuy_write_csv(qc$component,file.path(cfg$paths$yys,"abcd_component_qc.csv")); yuy_write_csv(qc$correlation,file.path(cfg$paths$yys,"abcd_component_correlation_qc.csv")); if(!qc$pass) stop("ABCD component QC failed; test outcomes were not used. Review 05_yys QC files.")
  w <- abcd$components$weight; rtr <- as.numeric(ztrain%*%w); rte <- as.numeric(ztest%*%w); ry <- as.numeric(zyang%*%w); mu<-mean(rtr); sig<-sd(rtr); if(!is.finite(sig)||sig<=0) stop("YYScore SD invalid")
  train_meta[,YYScore257:=(rtr-mu)/sig]; test_meta[,YYScore257:=(rte-mu)/sig]; yang[,YYScore257:=(ry-mu)/sig]
  yuy_write_csv(data.table(eid=train_meta$eid,YYScore257=train_meta$YYScore257),file.path(cfg$paths$yys,"yys_score_derivation.csv")); yuy_write_csv(data.table(eid=test_meta$eid,YYScore257=test_meta$YYScore257),file.path(cfg$paths$yys,"yys_score_test.csv")); yuy_write_csv(data.table(eid=yang$eid,YYScore257=yang$YYScore257),file.path(cfg$paths$yys,"yys_score_yang.csv")); yuy_write_json(list(mean_train=mu,sd_train=sig,component_qc_pass=qc$pass),file.path(cfg$paths$yys,"yys_formula_parameters.json"))
  train_out <- cbind(train_meta[,.(eid,y=incident_cad,score2_raw,YYScore257)],as.data.table(ptrain)); test_out <- cbind(test_meta[,.(eid,y=incident_cad,score2_raw,YYScore257)],as.data.table(ptest))
  fwrite(train_out,file.path(cfg$paths$matrices,"derivation_matrix.csv.gz"),na=""); fwrite(test_out,file.path(cfg$paths$matrices,"test_matrix.csv.gz"),na="")
  yuy_write_csv(data.table(feature_id=map$raw_feature,protein=map$protein,rank=map$rank),file.path(cfg$paths$matrices,"protein_features.csv")); yuy_write_json(list(protein_n=257,derivation_n=nrow(train_out),test_n=nrow(test_out),derivation_events=sum(train_out$y),test_events=sum(test_out$y),yang_n=nrow(yang),split_hash=readLines(file.path(cfg$paths$split,"split_hash.txt")),protein_hash=yuy_sha_text(map$raw_feature),paired_design_contract="YY extensions differ from their benchmark by YYScore257 only",score2_imputation=sc$params),file.path(cfg$paths$matrices,"matrix_manifest.json"))
  saveRDS(list(protein_median=med,protein_sd=sdev,features=map$raw_feature,score2_imputation=sc$params),file.path(cfg$paths$cache,"training_preprocess_parameters.rds"),compress=TRUE)
}
