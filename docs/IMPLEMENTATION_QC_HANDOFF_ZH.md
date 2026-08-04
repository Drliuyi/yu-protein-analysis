# 郁金泰团队 CVD 蛋白组文章复现：代码质控交接

## 1. 文章与代码可得性

- 文章：*Systematic analyses uncover plasma proteins linked to incident cardiovascular diseases*。
- DOI：`10.1093/procel/pwaf072`。
- 已归档：全文、Tables S1-S26、Figures S1-S5、主图 Figure 1-6。
- 未检索到作者公开的分析仓库、脚本、固定 split EID 或训练模型。
- 因此本项目属于“按正文和附件锁定的方法独立实现”，不是逐行复现作者未公开代码。

检索证据和局限见 `docs/CODE_AVAILABILITY_AUDIT.md`。

## 2. 两条代码轨道

### A. 全文章复现主轨

入口：`tools/run_yu_full_reproduction_windows.ps1`。

实现顺序：

1. 读取官方附件并导出参考表；
2. 建立基线无 14 类 CVD 的 incident cohort；
3. 以 2023-09-30 为随访截止；
4. 对实际保留的完整 Olink 面板执行 14 结局 Cox；
5. derivation 内 Bonferroni 筛选，形成跨结局候选联合；
6. 初步 LightGBM 计算 gain，每个结局取累计 gain 达 30% 的最小前缀；
7. 合并 14 个结局的蛋白，形成最终预测面板；
8. 构建 SCORE2、Protein、Protein+SCORE2；
9. 在锁定 hold-out 评估 AUC、accuracy、sensitivity、specificity、F1、Brier、DeLong、NRI/IDI 和 1000 次 bootstrap；
10. 生成本地 Figure 1、Figure 2、Figure 4 和补充图源数据。

论文锚点 `2920 / 671 / 257` 只用于核对，不会写死为本地结果。

### B. CAD 固定 257 蛋白快速审计轨

入口：`tools/run_yu_yys_windows.ps1`。

该轨直接读取官方 Table S12 中 CAD 对应的固定面板，用于快速验证 SCORE2、Protein、Protein+SCORE2 以及单列 YYScore 扩展。它不能代替全 14 结局筛选复现。

## 3. 已实现与输入受限模块

|模块|状态|说明|
|---|---|---|
|官方附件/方法审计|已实现|输出每张附件表及哈希|
|14 结局队列与 split|已实现|split 和 foldid 永久保存|
|全面板 Cox|已实现|蛋白缺失率阈值 30%，HR 按 scope 内 1 SD|
|671→30% gain→257|已实现|仅 derivation 选择|
|三个 LightGBM 模型|已实现|论文冻结参数|
|测试集评价|已实现|同时保留 IQR 与 95% CI，处理论文表述冲突|
|CMR|输入受限|需要 19 个 participant-level CMR 指标|
|MR/反向 MR|输入受限|需要 pQTL 与 CVD GWAS summary statistics、LD reference|
|PRS|输入受限|需要 genotype/PRSice 输出|
|Mediation|输入受限|需要冻结 risk-factor participant table|
|Metascape/STRING/TRRUST|外部会话受限|作者未公开数据库会话，必须记录版本、背景和阈值|

详细契约见 `config/external_module_contracts.csv`。

## 4. 质控时必须确认

1. `config/outcomes.csv` 恰好是官方 S10/S12 的 14 个预测结局。
2. `raw_protein_file` 是未预先插补的 baseline NPX 表，不能静默使用旧 `prot.rds`。
3. 正式全复现必须 `EndpointSubset=all`；单独 CAD 只能做烟雾测试。
4. `select` 阶段只读取 derivation EID 和蛋白，不能读取 test outcome。
5. test prediction 只在 257 联合面板、参数和模型全部冻结后产生。
6. 任何 `reference_*` 图片仅来自官方附件，不得写成“本地复现结果”。
7. 论文没有明确报告 split seed、分类阈值和完整调参空间；本地决定必须保留在 `config/method_provenance.csv`。

## 5. 仅质控、不启动正式模型的命令

```powershell
cd D:\UKB_data\scripts\yy_cad_yu_yys

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run_yu_full_reproduction_windows.ps1 `
  -Mode help

Rscript.exe --vanilla .\tests\test_full_reproduction.R
python .\tests\test_full_reproduction.py

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run_yu_full_reproduction_windows.ps1 `
  -Mode sources `
  -Dir0 D:/UKB_data
```

`sources` 只解析论文附件，不读取 UKB participant-level 数据，也不训练模型。
