# QC review checklist

- [ ] Official source workbook and methods PDF hashes match the source manifest.
- [ ] Table S12 contributes exactly 257 unique CAD proteins.
- [ ] All 257 names map to the raw local protein header.
- [ ] IL6 and TNF collapsed-assay limitations are explicitly reported.
- [ ] Baseline exclusion covers all 14 published CVD endpoints.
- [ ] Test EIDs and outcomes are not read during YYS construction.
- [ ] Derivation/test EIDs and ten-fold IDs are frozen and hashed.
- [ ] Paired benchmark matrices differ by exactly one column (`YYScore257`).
- [ ] SCORE2 isotonic calibration is fit on derivation data only.
- [ ] All five models use the same fixed LightGBM settings.
- [ ] No old FairK, ProtWAS, Top-K, XGBoost, RSF, Transformer, or Pradeep result is read.
- [ ] Primary comparison is YY combined versus standard combined.
- [ ] Negative or null YYScore results are retained.
