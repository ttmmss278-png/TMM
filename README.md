# TMM BioSeq Analysis Workbench

TMM BioSeq 是一个由 GitHub Pages 前端和本机 BioSeq Engine 组成的生物信息分析工作台。

## 在线入口

- 工作台：https://ttmmss278-png.github.io/TMM/
- WGS：https://ttmmss278-png.github.io/TMM/WGS/
- RNA-seq：https://ttmmss278-png.github.io/TMM/RNAseq/
- 小提琴图：https://ttmmss278-png.github.io/TMM/Violin/

## 使用方式

1. 下载或克隆本仓库到 Windows 电脑。
2. 双击 `BioSeq_Local_Service/BioSeq_Start.bat`。
3. 保持命令窗口开启，然后访问在线工作台。
4. 进入模块，选择文件、提交任务并预览或下载结果。

GitHub Pages 只提供网页界面。FASTQ、表达矩阵、参考基因组和分析结果均由本机 `http://127.0.0.1:8765` 服务处理，不会自动提交到 GitHub。

## 模块

- **WGS**：fastp、BWA、samtools，以及可选的 bcftools 变异检测。
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

## 本机环境

Python 依赖会由启动脚本根据 `backend/requirements.txt` 检查和安装。实际分析还需按模块安装：

- R 与 `Rscript`
- fastp
- BWA
- samtools
- bcftools（可选）
