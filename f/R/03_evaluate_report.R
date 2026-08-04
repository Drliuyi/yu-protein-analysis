yuy_auc <- function(y,p) as.numeric(pROC::auc(pROC::roc(y,p,quiet=TRUE,direction="<")))

yuy_metric_row <- function(d) {
  y<-d$y; p<-pmin(1-1e-9,pmax(1e-9,d$prediction)); pred<-as.integer(p>=d$threshold[[1]]); tp<-sum(pred==1&y==1); tn<-sum(pred==0&y==0); fp<-sum(pred==1&y==0); fn<-sum(pred==0&y==1)
  lp<-qlogis(p); cal_int<-tryCatch(coef(glm(y~offset(lp),family=binomial()))[[1]],error=function(e) NA_real_); cal_slope<-tryCatch(coef(glm(y~lp,family=binomial()))[[2]],error=function(e) NA_real_)
  data.table(n=length(y),events=sum(y),auc=yuy_auc(y,p),brier=mean((y-p)^2),accuracy=(tp+tn)/length(y),sensitivity=tp/pmax(tp+fn,1),specificity=tn/pmax(tn+fp,1),f1=2*tp/pmax(2*tp+fp+fn,1),threshold=d$threshold[[1]],calibration_intercept=cal_int,calibration_slope=cal_slope)
}

yuy_continuous_nri_idi <- function(y,pnew,pold) {
  up <- pnew>pold; down <- pnew<pold; cases<-y==1; controls<-y==0
  nri <- mean(up[cases])-mean(down[cases])+mean(down[controls])-mean(up[controls])
  idi <- (mean(pnew[cases])-mean(pnew[controls]))-(mean(pold[cases])-mean(pold[controls]))
  c(nri=nri,idi=idi)
}

yuy_evaluate <- function(cfg) {
  pf<-file.path(cfg$paths$models,"test_predictions.csv"); if(!file.exists(pf)) stop("Run train first: ",pf)
  pred<-fread(pf); models<-unique(pred$model_id); base<-rbindlist(lapply(models,function(m) cbind(data.table(model_id=m),yuy_metric_row(pred[model_id==m]))))
  set.seed(cfg$bootstrap_seed); boots<-vector("list",cfg$bootstrap_n)
  pairs<-data.table(
    comparison_id=c("PRIMARY_YY_COMBINED_vs_COMBINED","SECONDARY_YY_PROTEIN_vs_PROTEIN","PUBLISHED_STYLE_PROTEIN_vs_SCORE2","PUBLISHED_STYLE_COMBINED_vs_SCORE2"),
    new_model=c("Yu_SCORE2_Protein257_plus_YYScore257","Yu_Protein257_plus_YYScore257","Yu_Protein257","Yu_SCORE2_Protein257"),
    old_model=c("Yu_SCORE2_Protein257","Yu_Protein257","Yu_SCORE2","Yu_SCORE2")
  )
  wide<-dcast(pred,eid+y~model_id,value.var="prediction"); n<-nrow(wide)
  for(b in seq_len(cfg$bootstrap_n)) {
    idx<-sample.int(n,n,replace=TRUE); z<-wide[idx]; rows<-list()
    for(i in seq_len(nrow(pairs))) {
      nm<-pairs$new_model[[i]]; om<-pairs$old_model[[i]]; da<-tryCatch(yuy_auc(z$y,z[[nm]])-yuy_auc(z$y,z[[om]]),error=function(e) NA_real_); ni<-yuy_continuous_nri_idi(z$y,z[[nm]],z[[om]])
      rows[[i]]<-data.table(bootstrap=b,comparison_id=pairs$comparison_id[[i]],delta_auc=da,nri=ni[["nri"]],idi=ni[["idi"]])
    }
    boots[[b]]<-rbindlist(rows)
  }
  boot<-rbindlist(boots); yuy_write_csv(boot,file.path(cfg$paths$evaluation,"paired_bootstrap_replicates.csv.gz"))
  cmp<-rbindlist(lapply(seq_len(nrow(pairs)),function(i) {
    nm<-pairs$new_model[[i]]; om<-pairs$old_model[[i]]; a<-wide[[nm]]; b<-wide[[om]]; r1<-pROC::roc(wide$y,a,quiet=TRUE,direction="<"); r0<-pROC::roc(wide$y,b,quiet=TRUE,direction="<"); dt<-pROC::roc.test(r1,r0,paired=TRUE,method="delong"); bs<-boot[comparison_id==pairs$comparison_id[[i]]]; ni<-yuy_continuous_nri_idi(wide$y,a,b)
    data.table(comparison_id=pairs$comparison_id[[i]],new_model=nm,old_model=om,n=n,events=sum(wide$y),auc_new=as.numeric(pROC::auc(r1)),auc_old=as.numeric(pROC::auc(r0)),delta_auc=as.numeric(pROC::auc(r1)-pROC::auc(r0)),delta_auc_ci_low=quantile(bs$delta_auc,.025,na.rm=TRUE),delta_auc_ci_high=quantile(bs$delta_auc,.975,na.rm=TRUE),delong_p=dt$p.value,nri=ni[["nri"]],nri_ci_low=quantile(bs$nri,.025,na.rm=TRUE),nri_ci_high=quantile(bs$nri,.975,na.rm=TRUE),idi=ni[["idi"]],idi_ci_low=quantile(bs$idi,.025,na.rm=TRUE),idi_ci_high=quantile(bs$idi,.975,na.rm=TRUE))
  }))
  model_boot<-rbindlist(lapply(models,function(m) {
    d<-pred[model_id==m]; vals<-replicate(cfg$bootstrap_n,{idx<-sample.int(nrow(d),nrow(d),replace=TRUE); tryCatch(yuy_auc(d$y[idx],d$prediction[idx]),error=function(e) NA_real_)})
    data.table(model_id=m,auc_ci_low=quantile(vals,.025,na.rm=TRUE),auc_ci_high=quantile(vals,.975,na.rm=TRUE))
  }))
  base<-merge(base,model_boot,by="model_id",all.x=TRUE); yuy_write_csv(base,file.path(cfg$paths$evaluation,"test_model_metrics.csv")); yuy_write_csv(cmp,file.path(cfg$paths$evaluation,"paired_model_comparisons.csv"))
  pubfile<-file.path(cfg$script_dir,"f","config","yu_cad_published_metrics.csv"); if(file.exists(pubfile)) yuy_write_csv(fread(pubfile),file.path(cfg$paths$evaluation,"published_cad_reference_metrics.csv"))
  yuy_write_json(list(status="PASS",bootstrap_n=cfg$bootstrap_n,primary_comparison="PRIMARY_YY_COMBINED_vs_COMBINED",test_n=n,test_events=sum(wide$y),model_n=length(models)),file.path(cfg$paths$evaluation,"evaluation_summary.json"))
}

yuy_report <- function(cfg) {
  mf<-file.path(cfg$paths$evaluation,"test_model_metrics.csv"); cf<-file.path(cfg$paths$evaluation,"paired_model_comparisons.csv"); if(!file.exists(mf)||!file.exists(cf)) stop("Run evaluate first")
  m<-fread(mf); c<-fread(cf); p<-c[comparison_id=="PRIMARY_YY_COMBINED_vs_COMBINED"]
  lines<-c(
    "# Yu/Chen-style CAD 257-protein benchmark + YYScore257",
    "",
    "## Scope",
    "",
    "Published fixed 257-protein panel, SCORE2, and frozen LightGBM parameters with an independent local 2/3 derivation and 1/3 hold-out split.",
    "",
    sprintf("Hold-out N=%s; CAD events=%s.",format(p$n,big.mark=","),format(p$events,big.mark=",")),
    "",
    "## Primary result",
    "",
    sprintf("Combined+YYScore257 AUC %.4f versus standard combined AUC %.4f; paired delta %.4f (bootstrap 95%% CI %.4f to %.4f), DeLong P=%.4g.",p$auc_new,p$auc_old,p$delta_auc,p$delta_auc_ci_low,p$delta_auc_ci_high,p$delong_p),
    "",
    "## Model table",
    "",
    paste(c("|Model|AUC|95% CI|Brier|Calibration slope|","|---|---:|---:|---:|---:|",vapply(seq_len(nrow(m)),function(i) sprintf("|%s|%.4f|%.4f to %.4f|%.4f|%.3f|",m$model_id[[i]],m$auc[[i]],m$auc_ci_low[[i]],m$auc_ci_high[[i]],m$brier[[i]],m$calibration_slope[[i]]),character(1))),collapse="\n"),
    "",
    "## Interpretation rule",
    "",
    "The YY model differs from its paired benchmark by one derived feature only. A null or negative delta is retained as the scientific result and does not trigger formula revision against the hold-out set.",
    "",
    "## Limitations",
    "",
    "This is a Yu/Chen-style local implementation rather than a literal replication. The original split was unavailable, and local IL6/TNF features are assay-collapsed."
  )
  writeLines(lines,file.path(cfg$paths$report,"RESULTS_SUMMARY.md"))
  sources<-c(file.path(cfg$paths$preflight,"input_manifest.csv"),file.path(cfg$paths$preflight,"official_257_local_mapping.csv"),file.path(cfg$paths$split,"derivation_eid.csv"),file.path(cfg$paths$split,"test_eid.csv"),file.path(cfg$paths$split,"foldid.csv"),file.path(cfg$paths$yys,"abcd_yys_components.csv"),file.path(cfg$paths$models,"test_predictions.csv"),mf,cf)
  man<-rbindlist(lapply(sources,function(f) data.table(path=normalizePath(f,winslash="/",mustWork=TRUE),bytes=file.info(f)$size,sha256=yuy_sha_file(f)))); yuy_write_csv(man,file.path(cfg$paths$report,"formal_source_manifest.csv"))
}
