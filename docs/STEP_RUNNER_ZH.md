# Yu 蛋白组项目分步命令

## 入口

所有日常操作只使用项目根目录的 `yu.ps1` 或 `yu.sh`。底层 R、Python、
PowerShell 和 WSL 代码均在 `f/`，不需要用户逐个调用。

```powershell
.\yu.ps1 -Step help
```

WinPC WSL 或 Git Bash：

```bash
./yu.sh --help
./yu.sh 1-4 --resume
```

`yu.sh` 只转发到同一个 `yu.ps1` 主入口，因此两种命令使用完全相同的
冻结配置、检查点和结果目录。

## 第一次使用

项目默认采用黄老师 D 盘路径：

| 项目 | 默认路径 |
|---|---|
| 根目录 | `D:/` |
| 表型目录 | `D:/data/ukb/phe` |
| 脚本目录 | `D:/scripts` |
| 分析目录 | `D:/analysis` |
| 基因型 | `Z:/projects/genotype_pc_nas/imputed_pgen_autosomes` |

如果本机仍使用 `D:/UKB_data`，无需移动或复制数据。运行：

```powershell
.\yu.ps1 -Step setup
```

Shell 等价命令为 `./yu.sh setup`。

缺失路径会弹出选择框；SSH 环境改为终端输入。确认后的路径写入
`%LOCALAPPDATA%/YuProteinAnalysis/paths.json`，以后自动复用，且不会启动分析。

```powershell
.\yu.ps1 -Step paths                 # 查看当前路径
.\yu.ps1 -Step setup -ResetPaths     # 删除旧配置并重新设置
```

优先级为：命令参数/`YU_*` 环境变量 > 本机路径配置 > 黄老师默认路径。
无人值守任务可加 `-PathPromptMode Off`，路径缺失时立即失败。

## 步骤

| Step | 内容 | 资源 |
|---:|---|---|
| 1 | 来源审计与 preflight | 轻量 |
| 2 | incident CVD 队列 | 轻量 |
| 3 | 全面板分结局 Cox | 重计算 |
| 4 | derivation 筛选、LightGBM、hold-out 评价 | 重计算 |
| 5 | CMR 蛋白关联 | 重计算 |
| 6 | 两样本 MR | 中等 |
| 7 | 中介候选分析 | 中等 |
| 8 | CMAverse 正式中介 | 极重 |
| 9 | 13 结局 PRS、计分、蛋白关联和 Figure 6A | 极重 |
| 10 | 富集、TF、STRING-PPI 和 Figure 6B-D | 中等/联网 |
| 11 | 重绘 Figure 1-6 并生成报告 | 轻量 |

Step 8 和 9 必须显式增加 `-ConfirmHeavy`。

## 常用命令

运行主复现：

```powershell
.\yu.ps1 -Step "1-4" -Workers 16 -CoxJobs 4 -ModelJobs 3 -Resume
```

只预览：

```powershell
.\yu.ps1 -Step "1-4" -PlanOnly
```

读取状态：

```powershell
.\yu.ps1 -Step status
```

从已有结果重绘：

```powershell
.\yu.ps1 -Step figures -Resume
```

运行 PRS 与系统生物学：

```powershell
.\yu.ps1 -Step "9-11" -ConfirmHeavy -Resume
```

## 更换疾病或模型蛋白

`-Disease` 接受 `all`、单个结局或逗号分隔的多个结局；`-ProteinPanel`
接受 `local_reselected`、`published_257` 或 `custom`。自定义分析必须使用新的
`-AnalysisProject`，不能覆盖冻结的 `yu_proteomic_repo_v3`。

```powershell
.\yu.ps1 -Step "1-4" `
  -AnalysisProject yu_hf_custom_v1 `
  -Disease heart_failure `
  -ProteinPanel custom `
  -ModelProteinFile D:/files/hf_proteins.csv `
  -Workers 16 -Resume
```

少量蛋白可直接输入：

```powershell
.\yu.ps1 -Step "1-4" `
  -AnalysisProject yu_cad_inline_v1 `
  -Disease cad -ProteinPanel custom `
  -ModelProteins "GDF15,NPPB,ADM" -Resume
```

## 恢复与审计

- `-Resume` 复用有效 marker 和完成分片；
- `-Force` 仅用于明确重建所选步骤；
- 每次运行在分析目录 `00_logs` 保存步骤状态、解析路径、疾病、蛋白面板和错误；
- 路径配置位于本机用户目录，不进入 GitHub 或代码包；
- `yu.ps1` 固定 `YYScoreMode=off`，历史 YYScore 代码不进入正式复现。
