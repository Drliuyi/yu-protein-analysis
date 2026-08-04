# Figure 6A-D 全代码实现说明

## 定位

本模块从本地全量 incident CVD Cox 结果自动生成 Figure 6B-D，并将已完成的
本地 Figure 6A PRS-protein 热图并入最终组合图。B-D 不依赖
Metascape 网页操作或 Cytoscape 手工导出。它是对原文分析目标的可复现
等价实现，不宣称复原作者未公开的 Metascape session 或 Cytoscape session。

## 数据边界

- 本地输入：`05_cox/table_s2_incident_associations.csv.gz`。
- 前景：14 个结局中 Bonferroni 显著蛋白的基因符号并集。
- 背景：本地 Cox 分析实际检测的全部 Olink 蛋白，而不是全基因组。
- Figure 6A 的 PRS 蛋白不进入 Figure 6B-D 的富集或网络计算，仅作为最终
  组合图左侧整列显示。
- 同一结局内同 symbol 多 assay 仅保留 P 值最小的一条用于基因层面网络；
  assay 级原始显著结果另行完整保存。

## Figure 6B 富集分析

使用 MSigDB 2026.1 和本地检测蛋白背景执行超几何过度富集分析。五类
来源固定为 WikiPathways、KEGG、Canonical pathways（BioCarta/PID）、
GO Biological Process 和 Reactome。全部候选条目统一进行 BH 校正，阈值
为 FDR < 0.05。主图固定展示每类 FDR 最低的 2 个条目，共 10 个气泡；
完整结果不截断。

## Figure 6C CVD-protein-TF

每个结局按本地 Cox P 值选择前 15 个显著蛋白。TF-target 关系来自下载并
保存校验和的 TRRUST v2 human 表。完整关系全部输出；主图按 TF 涉及的
结局数、蛋白数、支持记录数和 symbol 顺序，展示前 46 个 TF。该规则只
控制图形可读性，不改变完整源表。Sankey 节点和 ribbon 的高度/宽度均按
实际 CVD-protein-TF 连接数加权；疾病使用完整名称，蛋白和 TF 标签交替
放置在节点条两侧。蛋白与 TF 节点颜色取其连接数最多的主导 CVD。

## Figure 6D PPI 和 hub

使用 STRING v12 functional network，物种为人类，默认 required score 为
700（high confidence）。网络以 MCODE 兼容参数识别致密模块：degree cutoff
2、node score cutoff 0.2、k-core 2、max depth 100、haircut on、fluff off。
主簇内 hub 使用 Maximum Neighborhood Component (MNC) 排序。主图内圈
为高 MNC hub 蛋白，外圈为其余主簇蛋白；节点大小映射 degree，连续颜色
映射 MNC，蛋白名称置于节点圆心。阈值和版本均写入 manifest；
不得根据图片是否好看再修改阈值。另输出内圈蛋白、外圈 TF 的调控网络
作为补充图，但不得将该补充图误写为 STRING PPI 主图。

## 一键命令

```powershell
cd D:\UKB_data\scripts\yy_cad_yu_yys

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run_yu_full_reproduction_windows.ps1 `
  -Mode figure6_systems `
  -Dir0 D:/UKB_data `
  -AnalysisProject yu_proteomic_repo_v3 `
  -StringRequiredScore 700 `
  -SystemsTopN 15 `
  -SystemsMaxTf 46 `
  -SystemsFdr 0.05 `
  -Resume
```

## 核心输出

- `14_enrichment/enrichment_results.csv`
- `14_enrichment/network_results.csv`
- `14_enrichment/local_cox_systems/figure6c_cvd_protein_tf_edges_all.csv`
- `14_enrichment/local_cox_systems/figure6d_mcode_compatible_clusters.csv`
- `15_figures/figure6b_local_cvd_protein_enrichment.*`
- `15_figures/figure6c_local_cvd_protein_tf_sankey.*`
- `15_figures/figure6c_supp_local_protein_tf_concentric.*`
- `15_figures/figure6d_local_string_ppi_mnc.*`
- `15_figures/figure6abcd_local_systems_biology.*`
- `15_figures/figure6bcd_local_systems_biology.*`

最终组合版式固定为 Figure 6A 占左侧整列，Figure 6B、6C、6D 在右侧
自上而下排列。`figure6bcd_local_systems_biology.*` 作为兼容旧网页链接的
同内容别名保留。

每张图均同时输出 PDF、PNG、600-dpi TIFF 和源数据。所有 API 原始响应、
参数、计数及 SHA256 均保留在 `14_enrichment/local_cox_systems`。
