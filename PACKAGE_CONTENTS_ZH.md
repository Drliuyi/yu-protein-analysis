# Yu 蛋白组分析代码包

## 公开结构

项目根目录只保留一个日常命令：

```powershell
.\yu.ps1 -Step help
```

所有分析实现统一放在 `f/`：

| 目录 | 内容 |
|---|---|
| `f/entry` | R 总入口 |
| `f/R` | 队列、Cox、CMR、MR、中介、PRS、系统生物学、作图和报告 |
| `f/python` | 蛋白筛选、LightGBM 和评估 |
| `f/tools` | Windows 调度、打包和辅助工具 |
| `f/wsl` | GWAS/PRS shell 阶段 |
| `f/config` | 冻结结局、字段、PRS 来源、阈值和方法配置 |
| `f/tests` | R、Python、PowerShell 和 PRS 测试 |

`docs/` 保存方法和 QC 文档，`references/` 保存可公开的文章补充材料与
来源清单。

## 路径接口

默认采用黄老师 `jielab/pub` 风格：`D:/data/ukb/phe`、`D:/scripts` 和
`D:/analysis`。当前 WinPC 仍可使用原来的 `D:/UKB_data` 物理目录：首次运行
执行 `\.\yu.ps1 -Step setup`，按提示选择真实路径，之后自动读取保存在
`%LOCALAPPDATA%/YuProteinAnalysis/paths.json` 的本机配置。代码不会移动数据，
也不会在 D 盘根目录创建兼容目录。

## 不包含

- UKB 个体级表型、蛋白、CMR、基因型和 PRS 数据；
- `analysis` 结果、模型对象、日志和缓存；
- Zspace/NAS 的 PGEN/PVAR/PSAM；
- Python 缓存、`Rplots.pdf`、PLINK 二进制；
- 密码、令牌、API key 或本机路径配置。

打包脚本会生成文件级 SHA256 清单和 ZIP 的 SHA256：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\f\tools\package_yu_project.ps1
```
