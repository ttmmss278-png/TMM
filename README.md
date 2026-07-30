# TMM BioSeq Analysis Workbench

TMM BioSeq 是一个由 GitHub Pages 前端和本机 BioSeq Engine 组成的生物信息分析工作台。

## 在线入口

- 工作台：https://ttmmss278-png.github.io/TMM/?v=20260730-5
- WGS：https://ttmmss278-png.github.io/TMM/WGS/?v=20260730-5
- RNA-seq：https://ttmmss278-png.github.io/TMM/RNAseq/?v=20260730-5
- 小提琴图：https://ttmmss278-png.github.io/TMM/Violin/?v=20260730-5

GitHub Pages 只提供网页界面。FASTQ、表达矩阵、参考基因组和分析结果均由本机 `http://127.0.0.1:8765` 服务处理，不会自动提交到 GitHub。

## WGS 离线便携包

WGS 不再在启动 BAT 中临时安装 `fastp`、`BWA`、`samtools` 和 `bcftools`。这些程序与便携 Python、BioSeq Engine v1.4.0 一起预先打包为：

- `TMM_BioSeq_Portable_WGS_v1.4.0.zip`
- 固定下载地址：https://github.com/ttmmss278-png/TMM/releases/download/bioseq-portable-v1.4.0/TMM_BioSeq_Portable_WGS_v1.4.0.zip
- SHA-256：https://github.com/ttmmss278-png/TMM/releases/download/bioseq-portable-v1.4.0/TMM_BioSeq_Portable_WGS_v1.4.0.zip.sha256

首次使用：

1. 下载并完整解压 ZIP。
2. 确认 Windows 已安装并初始化过 Ubuntu WSL。
3. 双击 `Install_TMM_BioSeq_Portable.bat`。
4. 安装器校验 SHA-256，然后只复制应用和便携 Python，并把预装 WGS 工具解压到 Ubuntu 的 `/opt/tmm-bioseq-wgs`。
5. 安装完成后，网页中的“启动”按钮调用本机 `BioSeq_Quick_Start.bat`。

离线安装器不会联网、不会运行 `apt`、不会在启动时安装 WGS 软件。

## 快速启动

完成离线包安装后，日常启动只执行：

```text
C:\Users\<用户名>\AppData\Local\TMMBioSeq\BioSeq_Quick_Start.bat
```

快速启动器只负责：

- 检查 BioSeq Engine v1.4.0 是否已经运行；
- 关闭占用 8765 端口的旧引擎；
- 使用便携 Python 启动 v1.4.0；
- 最多检测约 15 秒。

网页端不再执行 240 次环境轮询。缺少离线工具包时会立即停止等待，并显示下载按钮。

## 模块

- **WGS**：fastp、BWA、samtools，以及 bcftools 变异检测。
- **RNA-seq**：差异表达火山图、GO/KEGG 富集气泡图、表达热图。
- **Violin**：按一个或多个 Gene ID 绘制表达分布小提琴图。

## WGS 默认参考基因组

WGS 模块默认使用 `ToxoDB-68_TgondiiGT1_Genome.fasta`（Toxoplasma gondii GT1）。

首次使用时，在 WGS 页面选择该 FASTA，然后点击“仅安装/更新默认参考基因组”。BioSeq Engine 会校验文件大小和 SHA-256，并保存到本机 `reference_genomes` 目录。后续分析只需要选择 R1 和 R2，系统会自动复用默认参考基因组及其 BWA、samtools 索引。

已登记的校验信息：

- 文件大小：65,205,230 bytes
- SHA-256：`2d80433d0f2b5f605e79c11e263e15545bdb47e8dcbeb5f6b43c1843d1c27f40`
- 序列记录：2,063
- 总碱基数：63,945,332

## RNA-seq 与小提琴图环境

RNA-seq 和小提琴图由本机 R 环境执行。当前便携 WGS 包只包含 Python 和 WGS 命令行工具，不包含 R。运行绘图模块前，电脑仍需安装可用的 `Rscript` 和相应 R 包。