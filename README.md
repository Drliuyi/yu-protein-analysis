# Yu Protein Analysis

Yu/Chen 2025 UKB-PPP 蛋白组分析的可复现实现。项目仅保留一个公开入口：

```bash
./yu.sh --help
```

## 快速开始

```bash
./yu.sh setup
./yu.sh doctor
./yu.sh all --confirm-heavy --resume
```

在 WinPC PowerShell 中通过 WSL 调用同一个入口：

```powershell
wsl bash -lc "cd /mnt/d/UKB_data/scripts/yu-protein-analysis && ./yu.sh --help"
wsl bash -lc "cd /mnt/d/UKB_data/scripts/yu-protein-analysis && ./yu.sh all --confirm-heavy --resume"
```

`setup` 只确认并保存路径，不启动分析；`doctor` 检查数据、软件和代码；
`all` 执行完整流程。常用辅助命令：

```bash
./yu.sh status
./yu.sh figures --resume
./yu.sh finalize --resume
./yu.sh package
```

步骤可以单独、组合或按范围运行：

```bash
./yu.sh 3
./yu.sh 3,4
./yu.sh 1-4 --resume
```

| 步骤 | 内容 |
|---:|---|
| 1 | 文献来源、输入和面板质控 |
| 2 | 无基线 CVD 的 incident 队列 |
| 3 | 14 个结局的全蛋白 Cox 分析 |
| 4 | 训练集蛋白筛选、LightGBM 和留出集评估 |
| 5 | CMR 关联 |
| 6 | MR |
| 7 | 中介候选分析 |
| 8 | CMAverse 中介分析 |
| 9 | 13 个结局的 PRS-蛋白分析 |
| 10 | 富集、TF 和 STRING-PPI |
| 11 | Figure 1-6 和结果报告 |

步骤 8、9 耗时较长，需增加 `--confirm-heavy`。`--resume` 只复用通过
完整性校验的阶段和分片。

## 路径

默认采用黄老师项目的 D 盘接口：`D:/data/ukb/phe`、`D:/analysis`、
`D:/data.BIG/gwas/ppp`。在当前 WinPC 上会自动识别原有的
`D:/UKB_data` 目录，不移动数据，也不建立兼容链接。基因型默认从
`Z:/projects/genotype_pc_nas/imputed_pgen_autosomes` 直接读取。

路径不存在时，交互终端会要求输入；确认结果保存在当前用户配置目录。
也可以显式覆盖，例如：

```bash
./yu.sh 1-4 \
  --analysis-project yu_proteomic_repo_v3 \
  --raw-protein-file D:/UKB_data/phe/raw/prot_full_unimputed.tsv \
  --phenotype-rds D:/UKB_data/phe/Rdata/all.rds \
  --resume
```

更换疾病或模型蛋白时必须使用新的结果项目：

```bash
./yu.sh 2-4 \
  --analysis-project yu_avs_custom_v1 \
  --disease aortic_valve_stenosis \
  --protein-panel custom \
  --model-proteins GDF15,NPPB,ADM,CST3
```

## 目录

```text
yu.sh          唯一运行命令
f/entry        R 低层入口
f/R            分析和绘图
f/python       模型与 PRS
f/tools        内部调度和安装工具
f/config       冻结参数与映射
f/tests        自动检查
references     公开文献附件及来源清单
```

公开流程固定为 Yu/Chen 复现，不运行 YYScore，也不读取 FairK、ProtWAS、
Top-K 或其他旧项目结果。详细统计边界见 [METHODS_FROZEN.md](METHODS_FROZEN.md)，
交付检查见 [QC_REVIEW_CHECKLIST.md](QC_REVIEW_CHECKLIST.md)。
