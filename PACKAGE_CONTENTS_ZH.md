# Yu 蛋白组分析代码包内容

## 包的定位

本包是 Yu/Chen 蛋白组文章复现与本地扩展项目的可交付代码包。冻结主流程为
`YYScoreMode=off`，不会把历史 ABCD-YYS 试验结果混入正式 Yu 复现结果。

## 包含的九个部分

1. **统一入口**
   - `yu.ps1`
   - `tools/run_yu_steps_windows.ps1`
   - 提供 Step 1-11、路径自动解析、缺失路径选择框、状态与续跑。

2. **R 主分析代码**
   - `99_run_yu_full_reproduction.R`
   - `R/full/`
   - 包含来源审计、队列、Cox、CMR、MR、中介、PRS 关联、系统生物学、作图和报告。

3. **Python 建模代码**
   - `python/04_full_reproduction.py`
   - 其他训练、评估和历史审计脚本。
   - 包含蛋白筛选、LightGBM、预测评价及并行任务逻辑。

4. **Windows 调度代码**
   - `tools/*.ps1`
   - 管理 R/Python 环境、分片并行、恢复运行、日志和步骤状态。

5. **WSL 与 PRS 代码**
   - `99_run_yu_prs.R`
   - `wsl/`
   - `tools/score_prs_directnas_windows.py`
   - 包含 GWAS 权重准备、Z 盘直接读取、1-22 号染色体评分、合并和关联分析。

6. **冻结配置与映射**
   - `config/`
   - 包含 14 个 incident CVD 结局、PRS 来源和阈值、临床字段映射、蛋白映射与方法来源。

7. **测试与质量控制**
   - `tests/`
   - `QC_REVIEW_CHECKLIST.md`
   - 包含 R/Python 静态测试、PowerShell 解析测试、Figure 6、PRS 和直接 NAS 读取测试。

8. **方法与使用文档**
   - `README.md`
   - `METHODS_FROZEN.md`
   - `docs/`
   - 包含完整步骤、参数、方法来源、复现差异、运行模式和结果解释边界。

9. **原文复现参考材料**
   - `references/raw/`
   - 包含原文补充表、补充图、图像参考、Olink 日期定义和 CMAverse 固定源包。
   - 这些文件用于来源审计与图表核对，不是 UKB 个体级数据。

## 明确不包含

- `D:/UKB_data/analysis` 下的任何结果和模型对象。
- UKB 个体级表型、蛋白、CMR、基因型或 PRS 数据。
- Zspace/NAS 上的 PGEN/PVAR/PSAM。
- Python `__pycache__`、`*.pyc`、临时日志和 `Rplots.pdf`。
- 项目目录中的 `archive`、`backups` 和其他重复旧版代码快照。
- 本机 R/Python 环境、安装包缓存和 PLINK 二进制文件。
- 密码、令牌、API key 或其他凭据。

## 运行所需的外部目录

代码包解压后默认解析现有 WinPC 布局：

- `D:/UKB_data/phe`
- `D:/UKB_data/pheno.tsv.gz`
- `D:/UKB_data/ppp`
- `D:/UKB_data/analysis`
- `Z:/projects/genotype_pc_nas/imputed_pgen_autosomes`

若路径不同，运行 `yu.ps1` 时会要求选择对应文件或目录。查看全部步骤：

```powershell
.\yu.ps1 -Step help
```

## 完整性校验

压缩包根目录中的 `FILE_MANIFEST_SHA256.csv` 记录每个纳入文件的相对路径、
字节数和 SHA256。压缩包旁的 `.sha256` 文件记录 ZIP 本身的 SHA256。
