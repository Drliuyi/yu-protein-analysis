#!/usr/bin/env python
import argparse, json, os, hashlib
import numpy as np
import pandas as pd
from sklearn.isotonic import IsotonicRegression
from sklearn.metrics import roc_auc_score, roc_curve
from lightgbm import LGBMClassifier

def sha_text(values):
    return hashlib.sha256("\n".join(map(str, values)).encode()).hexdigest()

def youden(y, p):
    fpr, tpr, thr = roc_curve(y, p)
    ok = np.isfinite(thr)
    idx = np.argmax((tpr-fpr)[ok])
    return float(thr[ok][idx])

def build_model(params, workers, seed):
    return LGBMClassifier(
        objective="binary", n_estimators=int(params["n_estimators"]),
        max_depth=int(params["max_depth"]), num_leaves=int(params["num_leaves"]),
        subsample=float(params["subsample"]), subsample_freq=int(params["subsample_freq"]),
        learning_rate=float(params["learning_rate"]), colsample_bytree=float(params["colsample_bytree"]),
        random_state=int(seed), n_jobs=int(workers), verbosity=-1
    )

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--analysis-dir",required=True); ap.add_argument("--config",required=True); ap.add_argument("--workers",type=int,default=16); ap.add_argument("--resume",action="store_true"); args=ap.parse_args()
    with open(args.config,encoding="utf-8") as f: cfg=json.load(f)
    ad=args.analysis_dir; mdir=os.path.join(ad,"07_models"); os.makedirs(mdir,exist_ok=True)
    pred_file=os.path.join(mdir,"test_predictions.csv")
    if args.resume and os.path.exists(pred_file): print("Resume: test_predictions.csv exists; skipping train"); return
    train=pd.read_csv(os.path.join(ad,"06_matrices","derivation_matrix.csv.gz")); test=pd.read_csv(os.path.join(ad,"06_matrices","test_matrix.csv.gz")); feat=pd.read_csv(os.path.join(ad,"06_matrices","protein_features.csv")); folds=pd.read_csv(os.path.join(ad,"04_split","foldid.csv"))
    proteins=feat["feature_id"].tolist(); train=train.merge(folds,on="eid",how="left",validate="one_to_one")
    if train["foldid"].isna().any(): raise RuntimeError("Missing fold IDs")
    y=train["y"].astype(int).to_numpy(); yt=test["y"].astype(int).to_numpy(); params=cfg["lightgbm"]
    specs={
      "Yu_SCORE2":["SCORE2_calibrated"],
      "Yu_Protein257":proteins,
      "Yu_SCORE2_Protein257":proteins+["SCORE2_calibrated"],
      "Yu_Protein257_plus_YYScore257":proteins+["YYScore257"],
      "Yu_SCORE2_Protein257_plus_YYScore257":proteins+["SCORE2_calibrated","YYScore257"]
    }
    if set(specs["Yu_SCORE2_Protein257_plus_YYScore257"])-set(specs["Yu_SCORE2_Protein257"])!={"YYScore257"}: raise RuntimeError("Primary paired matrix contract failed")
    if set(specs["Yu_Protein257_plus_YYScore257"])-set(specs["Yu_Protein257"])!={"YYScore257"}: raise RuntimeError("Secondary paired matrix contract failed")
    oof={k:np.full(len(train),np.nan) for k in specs}; fold_rows=[]
    for fold in sorted(train.foldid.unique()):
        tr=train.foldid.to_numpy()!=fold; va=~tr
        iso=IsotonicRegression(out_of_bounds="clip").fit(train.loc[tr,"score2_raw"],y[tr])
        tr_score=iso.transform(train.loc[tr,"score2_raw"]); va_score=iso.transform(train.loc[va,"score2_raw"])
        a=train.loc[tr].copy(); b=train.loc[va].copy(); a["SCORE2_calibrated"]=tr_score; b["SCORE2_calibrated"]=va_score
        for n,cols in specs.items():
            mod=build_model(params,args.workers,int(params["random_state"])+int(fold)); mod.fit(a[cols],y[tr]); pv=mod.predict_proba(b[cols])[:,1]; oof[n][va]=pv
            fold_rows.append({"model_id":n,"fold":int(fold),"n":int(va.sum()),"events":int(y[va].sum()),"auc":float(roc_auc_score(y[va],pv))})
    iso=IsotonicRegression(out_of_bounds="clip").fit(train["score2_raw"],y); train["SCORE2_calibrated"]=iso.transform(train["score2_raw"]); test["SCORE2_calibrated"]=iso.transform(test["score2_raw"])
    pred=[]; imp=[]; summaries=[]
    for n,cols in specs.items():
        threshold=youden(y,oof[n]); mod=build_model(params,args.workers,int(params["random_state"])); mod.fit(train[cols],y); pt=mod.predict_proba(test[cols])[:,1]
        mod.booster_.save_model(os.path.join(mdir,n+".txt")); pred.append(pd.DataFrame({"eid":test.eid,"y":yt,"model_id":n,"prediction":pt,"threshold":threshold}))
        imp.append(pd.DataFrame({"model_id":n,"feature":cols,"importance_gain":mod.booster_.feature_importance(importance_type="gain"),"importance_split":mod.booster_.feature_importance(importance_type="split")}))
        summaries.append({"model_id":n,"n_features":len(cols),"oof_auc":float(roc_auc_score(y,oof[n])),"threshold_youden_oof":threshold,"test_auc_preview_not_for_tuning":float(roc_auc_score(yt,pt))})
    pd.concat(pred).to_csv(pred_file,index=False); pd.concat(imp).to_csv(os.path.join(mdir,"feature_importance.csv"),index=False); pd.DataFrame(fold_rows).to_csv(os.path.join(mdir,"derivation_fold_metrics.csv"),index=False)
    pd.DataFrame({"eid":np.tile(train.eid,len(specs)),"y":np.tile(y,len(specs)),"model_id":np.repeat(list(specs),len(train)),"oof_prediction":np.concatenate([oof[k] for k in specs])}).to_csv(os.path.join(mdir,"derivation_oof_predictions.csv"),index=False)
    with open(os.path.join(mdir,"model_summary.json"),"w",encoding="utf-8") as f: json.dump({"models":summaries,"protein_n":len(proteins),"protein_hash":sha_text(proteins),"parameters":params,"score2_isotonic_training_only":True,"paired_contract_pass":True,"versions":{"python":__import__('sys').version,"lightgbm":__import__('lightgbm').__version__,"sklearn":__import__('sklearn').__version__}},f,indent=2)
    pd.DataFrame({"eid":train.eid,"score2_raw":train.score2_raw,"score2_calibrated":train.SCORE2_calibrated}).to_csv(os.path.join(mdir,"score2_isotonic_derivation.csv"),index=False)
    pd.DataFrame({"eid":test.eid,"score2_raw":test.score2_raw,"score2_calibrated":test.SCORE2_calibrated}).to_csv(os.path.join(mdir,"score2_isotonic_test.csv"),index=False)
    print(json.dumps({"status":"PASS","models":len(specs),"test_n":len(test),"protein_n":len(proteins)}))
if __name__=="__main__": main()
