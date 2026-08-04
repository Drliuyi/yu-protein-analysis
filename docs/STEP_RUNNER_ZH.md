# Yu 蛋白组项目统一分步命令

## 定位

统一入口为：

```text
yu.ps1
```

它会转交给 `tools/run_yu_steps_windows.ps1`，只负责编排现有、已经验证的
R/Python/PRS 入口，不重写统计模型，不改变
结局、蛋白筛选、LightGBM、MR、中介、PRS 或作图方法。冻结的 Yu 主流程始终
使用 `YYScoreMode=off`；历史 YYScore 仅保留审计，不进入此命令。

## WinPC 默认目录与弹窗

以下目录已经设为默认值，正常情况下不再需要逐项写在命令中：

| 项目 | 默认路径 |
|---|---|
| 数据根目录 | `D:/UKB_data` |
| 项目代码 | `D:/UKB_data/scripts/yy_cad_yu_yys` |
| 表型 RDS | `D:/UKB_data/phe/Rdata/all.rds` |
| 未插补蛋白 | `D:/UKB_data/phe/raw/prot_full_unimputed.tsv` |
| 原始表型 | `D:/UKB_data/pheno.tsv.gz` |
| Olink 映射 | `D:/UKB_data/ppp/map.raw/olink_protein_map_3k_v1.tsv` |
| 分析结果 | `D:/UKB_data/analysis/<AnalysisProject>` |
| 基因型 | `Z:/projects/genotype_pc_nas/imputed_pgen_autosomes` |

入口只检查本次 `-Step` 真正需要的路径。默认路径不存在时，本机 PowerShell
自动弹出文件或文件夹选择框；通过 SSH 运行时自动改为终端逐项输入。弹窗只
改变本次运行的解析路径，最终路径会写入 step-runner 状态 JSON，底层分析代码
仍为非交互模式。

- `-PathPromptMode Auto`：默认，本机弹窗，SSH 使用终端输入。
- `-PathPromptMode Dialog`：强制 Windows 选择框。
- `-PathPromptMode Console`：强制终端输入。
- `-PathPromptMode Off`：用于无人值守任务，缺路径立即报错，不等待输入。
- `-PlanOnly`：只显示计划和缺失项，不弹窗、不计算。

## 步骤

| Step | 内容 | 主要依赖 | 资源 |
|---:|---|---|---|
| 1 | 来源审计与 preflight | 无 | 轻量 |
| 2 | 14 类 incident CVD 队列 | 1 | 轻量 |
| 3 | 2,920 蛋白的分结局 Cox | 2 | 重计算 |
| 4 | derivation 筛选、LightGBM、holdout 评价 | 3 | 重计算 |
| 5 | CMR 蛋白关联 | 2 | 重计算 |
| 6 | 本地两样本 MR | 3 | 中等 |
| 7 | 中介候选路径与快速中介分析 | 3 | 中等 |
| 8 | CMAverse 正式中介、分片与合并 | 7 | 极重 |
| 9 | 13 个 PRS 的 GWAS、计分、蛋白关联和 Figure 6A | 2 | 极重 |
| 10 | 富集、TF、STRING-PPI 与 Figure 6B-D | 3、9 | 中等/联网 |
| 11 | 从既有结果重绘 Figure 1–6，并汇总正式报告 | 4、5、6、8、10 | 轻量 |

Step 8 和 9 必须显式增加 `-ConfirmHeavy`。这能防止误启动 CMAverse 或
1-22 号染色体 PRS 计分。

## 可选疾病与模型蛋白

统一入口现在提供两组独立参数：

- `-Disease`：`all`、一个结局 ID，或逗号分隔的多个结局 ID。
- `-ProteinPanel`：`local_reselected`、`published_257` 或 `custom`。
- `-ModelProteinFile`：自定义蛋白 CSV/TSV/TXT 文件。
- `-ModelProteins`：少量蛋白可直接用逗号分隔输入。

可选结局 ID 为：`abdominal_aneurysm`、`atrial_fibrillation`、
`aortic_valve_stenosis`、`cad`、`cardiomyopathy`、`deep_vein_thrombosis`、
`heart_failure`、`intracerebral_hemorrhage`、`ischemic_stroke`、
`peripheral_arterial_disease`、`pulmonary_embolism`、
`subarachnoid_hemorrhage`、`thoracic_aneurysm` 和
`transient_ischemic_attack`。`-Step help` 会同时打印 ID 与英文标签。

三种蛋白面板的含义：

| 参数 | 进入预测模型的蛋白 |
|---|---|
| `local_reselected` | 在所选疾病 derivation 数据中按 Yu 流程重新筛选的蛋白并集 |
| `published_257` | 论文补充表 S12 的固定 257 蛋白 |
| `custom` | 用户指定的本地蛋白特征列，不再用筛选结果决定模型输入 |

自定义文件优先读取 `feature_id`、`local_feature`、`protein` 或 `assay` 列；
也接受只有一列且带表头的文件。每个值可以是未插补原始蛋白表中的本地特征
列名（不区分大小写），或能通过正式 panel mapping 唯一对应到一个 assay 的
gene symbol/Assay/OlinkID/UniProt。代码会逐个核对；同一 symbol 对应多个 assay
时硬失败并要求明确指定本地特征列，不会静默挑选。
解析后的逐项对应关系保存在 `08_selection/custom_protein_identifier_mapping.csv`。

更换疾病或蛋白面板时必须使用新的 `-AnalysisProject`。冻结项目
`yu_proteomic_repo_v3` 已受保护，非默认配置不能覆盖它。Step 9 是论文固定的
13 结局 PRS 重建模块，不随 `-Disease` 或 `-ProteinPanel` 改变。

## 常用命令

在 WinPC 中进入项目目录：

```powershell
cd D:\UKB_data\scripts\yy_cad_yu_yys
```

查看帮助：

```powershell
.\yu.ps1 -Step help
```

只预览，不运行：

```powershell
.\yu.ps1 `
  -Step "1-4" `
  -AnalysisProject yu_proteomic_repo_v3 `
  -PlanOnly
```

运行主队列、Cox 和预测：

```powershell
.\yu.ps1 `
  -Step "1-4" `
  -AnalysisProject yu_proteomic_repo_v3 `
  -Workers 16 -CoxJobs 4 -ModelJobs 3 `
  -BootstrapN 1000 `
  -Resume
```

仅分析心衰，并由本地 derivation 数据按 Yu 方法重筛模型蛋白：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run_yu_steps_windows.ps1 `
  -Step "1-4" `
  -Dir0 D:/UKB_data `
  -AnalysisProject yu_hf_local_v1 `
  -Disease heart_failure `
  -ProteinPanel local_reselected `
  -Workers 16 -CoxJobs 4 -ModelJobs 3 `
  -Resume
```

同时分析 CAD 和心衰，使用固定论文 257 蛋白：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run_yu_steps_windows.ps1 `
  -Step "1-4" `
  -Dir0 D:/UKB_data `
  -AnalysisProject yu_cad_hf_published257_v1 `
  -Disease "cad,heart_failure" `
  -ProteinPanel published_257 `
  -Workers 16 -CoxJobs 4 -ModelJobs 3 `
  -Resume
```

使用自定义蛋白文件建立 CAD 模型：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run_yu_steps_windows.ps1 `
  -Step "1-4" `
  -Dir0 D:/UKB_data `
  -AnalysisProject yu_cad_custom_v1 `
  -Disease cad `
  -ProteinPanel custom `
  -ModelProteinFile D:/UKB_data/files/cad_model_proteins.csv `
  -Workers 16 -CoxJobs 4 -ModelJobs 3 `
  -Resume
```

少量蛋白也可直接输入。下例中的 Step 4 仅适用于同一
`yu_cad_inline_v1` 项目已经完成 Steps 1-3 的情况；全新项目应运行 `-Step "1-4"`：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run_yu_steps_windows.ps1 `
  -Step 4 `
  -Dir0 D:/UKB_data `
  -AnalysisProject yu_cad_inline_v1 `
  -Disease cad `
  -ProteinPanel custom `
  -ModelProteins "GDF15,NPPB,ADM" `
  -Workers 16 -ModelJobs 3 `
  -Resume
```

只补 MR、快速中介和正式报告：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run_yu_steps_windows.ps1 `
  -Step "6,7,11" `
  -Dir0 D:/UKB_data `
  -AnalysisProject yu_proteomic_repo_v3 `
  -Workers 16 `
  -Resume
```

正式 CMAverse 中介：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run_yu_steps_windows.ps1 `
  -Step 8 `
  -Dir0 D:/UKB_data `
  -AnalysisProject yu_proteomic_repo_v3 `
  -Workers 16 -CmestJobs 8 -BootstrapN 1000 `
  -ConfirmHeavy -Resume
```

PRS 与 Figure 6：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run_yu_steps_windows.ps1 `
  -Step "9-11" `
  -Dir0 D:/UKB_data `
  -AnalysisProject yu_proteomic_repo_v3 `
  -Workers 16 -ScoreJobs 2 -AssociationJobs 4 -MemoryMb 48000 `
  -GenotypeMode DirectNas `
  -WindowsNasRoot Z:/projects/genotype_pc_nas/imputed_pgen_autosomes `
  -ConfirmHeavy -Resume
```

当前置分析均已完成，只重绘全部正式 Figure 1–6 和报告：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run_yu_steps_windows.ps1 `
  -Step figures `
  -Dir0 D:/UKB_data `
  -AnalysisProject yu_proteomic_repo_v3 `
  -Resume
```

Step 11 会先重绘 Figure 1–5 与本地 Figure 6A，再从 Step 10 已冻结的
富集、TF 和 STRING-PPI 源数据重绘 Figure 6B–D 及 Figure 6ABCD 总图。

读取状态，不修改任何结果：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run_yu_steps_windows.ps1 `
  -Step status `
  -Dir0 D:/UKB_data `
  -AnalysisProject yu_proteomic_repo_v3
```

## Resume 与状态文件

- `-Resume`：复用通过的 done marker 和分片结果。
- `-Force`：仅在明确需要重建所选步骤时使用。
- 每次正式运行在 `00_logs/step_runner_时间.json` 保存所选步骤、当前步骤、
  已完成步骤、疾病 ID、蛋白面板、自定义蛋白来源、解析后的根目录和错误信息。
- `selection_summary.json` 和 `training_manifest.json` 保存疾病列表、蛋白数量与
  蛋白 hash。更换疾病或蛋白后，`-Resume` 不会误跳过旧训练。
- 某一步失败后不会继续后续步骤；修复后使用相同 `-Step` 加 `-Resume` 即可。

## 路径覆盖

入口支持 `-Dir0`、`-ProjectDir`、`-PheDir` 和 `-AnalysisRoot`，并优先读取
`YU_DIR0`、`YU_PROJECT_DIR`、`YU_PHEDIR`、`YU_OUTDIR` 环境变量。WinPC 默认
直接使用现有 `D:/UKB_data` 物理目录，不创建或要求任何 D 盘根目录兼容层。
仅当数据确实位于其他位置时才需要覆盖参数或按弹窗选择。
