# Yu/Chen 蛋白组复现精度修复（2026-07-16）

## 为什么旧结果不能直接展示

旧运行虽然所有程序阶段均显示 PASS，但 `all.rds$total_cholesterol` 中混有与 mmol/L 不兼容的数值，导致 SCORE2 大量饱和为 1。因此，旧运行中的 Protein-only 结果可用于工程审计，但 SCORE2、Protein+SCORE2、NRI、IDI、DeLong 和 Figure 4 不能作为正式复现结果。

## 已修复项目

1. SCORE2 总胆固醇固定优先使用 `bb_TC`，HDL 固定优先使用 `bb_HDL`，单位均为 mmol/L。
2. Preflight 输出所有候选来源的分布，并对年龄、SBP、总胆固醇和 HDL 执行范围硬门禁。
3. Cohort 阶段再次检查 derivation/test 的脂质分布、SCORE2 非缺失率、边界饱和比例和有效唯一值；不合格直接停止。
4. 主预测面板由本地 derivation 集按论文方法重新筛选：Bonferroni 候选并集、逐结局 LightGBM gain 排序、累计 30% 后跨 14 结局取并集。
5. Supplementary Table S12 发布的 257 蛋白独立保存为论文参考面板，不进入主模型，也不影响本地筛选及后续 YYScore 扩展。
6. 正式环境强制 Python 3.9 和 LightGBM 3.3.2；版本不符时在模型运行前停止。
7. CAD 输出本地 AUC 与论文 Table S10 的逐模型差值表。
8. 正式运行使用全新 analysis project，避免旧 marker、旧 SCORE2 或旧选模文件被 `-Resume` 复用。
9. 论文没有公开精确 split seed、split EID、调参搜索空间和统一行政截止日；这些仍明确标记为本地冻结参数，不能伪称逐行作者代码复现。

## 正式结果解释

- `local_reselected`：在本地冻结 derivation split 上按论文方法重新筛选，是主分析和后续 YYScore 扩展轨。
- `published_257`：论文已发布模型输入的固定面板，只作参考和敏感性分析。
- 两者不应混称。由于论文没有发布作者代码、split EID、随机种子和调参搜索空间，本地重筛数量不要求机械等于 257。
- 正式展示前必须确认 `04_cohort/score2_input_output_qc.csv` 全部 PASS，并同时报告本地筛选数量、与论文 257 面板的重叠及 `10_evaluation/cad_prediction_replication_qc.csv`。
