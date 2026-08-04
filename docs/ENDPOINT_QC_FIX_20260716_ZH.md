# Yu proteomic reproduction 端点 QC 修复记录

## 结论

`D:/UKB_data/analysis/yu_proteomic_repo` 仅保留为 preliminary archive。该目录的 14 个 Cox 分片虽然已经计算完成，但其中腹主动脉瘤、胸主动脉瘤和深静脉血栓的上游日期定义不合格；因为基线 14-CVD 排除依赖全部端点，原队列、拆分及所有 Cox 结果均不得进入正式表图。

正式重算目录固定为：

`D:/UKB_data/analysis/yu_proteomic_repo_v2`

旧目录不会被覆盖。

## 根因

1. 早期全部 Cox 分片同时报错，直接原因是 PowerShell 并行调度器在重定向流尚未完成时读取进程退出码。调度器已经改为 `WaitForExit()` 后读取 `ExitCode`。
2. `fod_ref_cvd_abaneu` 与 `fod_ref_cvd_thaneu` 在 `all.rds` 的 501,937 行中完全相同。上游 `get_fod()` 用正则匹配 `fod.date0.rds` 列名，腹部和胸部主动脉瘤的模式发生了错误重叠。
3. `fod_ref_cvd_dvt` 只有 547 个非缺失日期，而医院 ICD10 DVT 日期有 6,702 个，导致旧队列仅有训练 32、测试 8 个 DVT 事件。
4. 这三个端点参与“基线无全部 14 种 CVD”的排除，因此不是只补跑三个 Cox 分片的问题；修复会改变整个 incident 队列、固定拆分、蛋白缺失率及每一个 Cox 模型。

## 论文来源锁定

依据官方 Supplementary Table 24：

- 腹主动脉瘤：ICD10 `I71.3/I71.4`，ICD9 `441.3/441.4`，加死亡登记 40001/40002。
- 胸主动脉瘤：ICD10 `I71.1/I71.2`，ICD9 `441.1/441.2`，加死亡登记 40001/40002。
- DVT：ICD10 `I80.2`，ICD9 `451.1`，加死亡登记 40001/40002。

三个端点不再读取错误的 `fod_ref_*`。其余端点保留论文 first-occurrence 字段，并补医院 ICD 与死亡登记来源。

## 新增硬门禁

- 端点定义列和 S24 death ICD10 前缀必须完整。
- 任意两个端点的完整日期向量完全相同则立即停止。
- 任意两个端点的 incident 事件向量完全相同则立即停止。
- 每个结局要求训练事件不少于 20、测试事件不少于 10、总事件不少于 50。
- 固定保存 outcome definition、split、事件/时间和 cohort contract SHA256。
- 每个 Cox 分片保存独立 contract JSON；`-Resume` 仅复用 hash 完全一致的分片。
- merge 拒绝任何旧队列、旧端点定义或旧蛋白面板产生的分片。

## WinPC 轻量验收结果

- incident cohort：47,485
- derivation：31,656
- hold-out：15,829
- CAD Yang auxiliary：1,913
- 腹主动脉瘤：训练 138，测试 90，总计 228
- DVT：训练 296，测试 153，总计 449
- 胸主动脉瘤：训练 73，测试 35，总计 108
- 14 个端点全部通过事件数门禁
- 完全重复日期端点对：0

核心 QC 文件：

- `04_cohort/outcome_source_coverage.csv`
- `04_cohort/outcome_pairwise_duplicate_qc.csv`
- `04_cohort/outcome_event_pairwise_qc.csv`
- `04_cohort/endpoint_event_summary.csv`
- `04_cohort/outcome_definition_hash.txt`
- `04_cohort/cohort_contract_hash.txt`

## 正式续跑命令

已完成 `preflight` 和 `cohort`，从现有合格检查点继续：

```powershell
cd D:\UKB_data\scripts\yy_cad_yu_yys

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run_yu_full_reproduction_windows.ps1 `
  -Mode all_fast `
  -Dir0 D:/UKB_data `
  -AnalysisProject yu_proteomic_repo_v2 `
  -RawProteinFile D:/UKB_data/phe/raw/prot_full_unimputed.tsv `
  -PhenotypeRds D:/UKB_data/phe/Rdata/all.rds `
  -RawPhenotypeFile D:/UKB_data/pheno.tsv.gz `
  -PanelMappingFile D:/UKB_data/ppp/map.raw/olink_protein_map_3k_v1.tsv `
  -EndpointSubset all `
  -Workers 16 `
  -CoxJobs 4 `
  -ModelJobs 3 `
  -BootstrapN 1000 `
  -Resume
```

不要添加 `-Force`，不要使用旧分析目录名。
