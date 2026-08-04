# 郁金泰文章复现与 YYScore 扩展运行边界

## 冻结原则

本项目默认只执行郁金泰/Chen 2025 文章的本地 source-locked 复现。
`YYScore` 是后续 CAD 专属扩展，不属于文章复现本体，必须通过命令显式开启。

| 参数 | 执行内容 | 是否读取 YYScore 文件 | CAD 模型 |
|---|---|---:|---|
| `-YYScoreMode off` | 文章复现，默认 | 否 | SCORE2、Protein、Protein+SCORE2 |
| `-YYScoreMode on` | 文章复现基础上的 YY 扩展 | 是，缺失即失败 | 上述三类 + 两个成对 YYScore 模型 |

## 第一阶段：只复现文章

```powershell
cd D:\UKB_data\scripts\yy_cad_yu_yys

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\f\tools\run_yu_full_reproduction_windows.ps1 `
  -Mode all_fast `
  -Dir0 D:/UKB_data `
  -AnalysisProject yu_proteomic_repo_v2 `
  -RawProteinFile D:/UKB_data/phe/raw/prot_full_unimputed.tsv `
  -PhenotypeRds D:/UKB_data/phe/Rdata/all.rds `
  -RawPhenotypeFile D:/UKB_data/pheno.tsv.gz `
  -PanelMappingFile D:/UKB_data/ppp/map.raw/olink_protein_map_3k_v1.tsv `
  -Workers 16 `
  -CoxJobs 4 `
  -ModelJobs 3 `
  -BootstrapN 1000 `
  -YYScoreMode off `
  -Resume
```

该模式不会运行 `yys` 阶段，即使结果目录中残留旧 YYScore 文件，训练代码也不会读取。

## 第二阶段：可选 YYScore 扩展

完成并冻结文章复现后，才运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\f\tools\run_yu_full_reproduction_windows.ps1 `
  -Mode all_fast `
  -Dir0 D:/UKB_data `
  -AnalysisProject yu_proteomic_repo_v2 `
  -RawProteinFile D:/UKB_data/phe/raw/prot_full_unimputed.tsv `
  -Workers 16 `
  -CoxJobs 4 `
  -ModelJobs 3 `
  -BootstrapN 1000 `
  -YYScoreMode on `
  -Resume
```

`-Resume` 会复用已验证的来源、队列、Cox 和蛋白筛选结果；YYScore 模型训练及其下游评价会按 `on` 模式重新生成。

## 运行门禁

1. `-Mode yys` 但未指定 `-YYScoreMode on` 时硬失败。
2. `-YYScoreMode off` 时禁止自动探测或读取 YYScore 文件。
3. `-YYScoreMode on` 时要求 derivation/test 两个 YYScore 文件齐全，否则硬失败。
4. 训练断点续跑必须同时匹配 `yys_mode_requested`，不能把纯复现训练误当作 YY 扩展训练。
5. 评价、图片和报告的完成标记区分 `yys_off` 与 `yys_on`。
