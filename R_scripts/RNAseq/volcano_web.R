args <- commandArgs(trailingOnly = TRUE)
if(length(args) < 2) stop('Usage: Rscript volcano_web.R input output')
input <- args[1]; out <- args[2]
dir.create(out, recursive=TRUE, showWarnings=FALSE)

pick_file <- function(path, patterns){
  if(file.exists(path) && !isTRUE(file.info(path)$isdir)) return(path)
  files <- list.files(path, recursive=TRUE, full.names=TRUE)
  files <- files[grepl('\\.(csv|tsv|txt)$', files, ignore.case=TRUE)]
  hit <- files[grepl(paste(patterns, collapse='|'), basename(files), ignore.case=TRUE)]
  if(length(hit)) hit[1] else if(length(files)) files[1] else stop('No readable DEG file found')
}
read_auto <- function(file){
  if(grepl('\\.csv$', file, ignore.case=TRUE)) read.csv(file, check.names=FALSE, stringsAsFactors=FALSE)
  else read.delim(file, check.names=FALSE, stringsAsFactors=FALSE)
}
find_col <- function(names, candidates){
  normal <- gsub('[^a-z0-9]','',tolower(names))
  index <- match(candidates, normal, nomatch=0)
  index <- index[index>0]
  if(length(index)) index[1] else NA_integer_
}

file <- pick_file(input, c('deg','diff','differential'))
data <- read_auto(file)
fc_col <- find_col(names(data), c('log2foldchange','log2fc','logfc','foldchange'))
p_col <- find_col(names(data), c('padj','fdr','adjpvalue','pvalue','pval'))
if(is.na(fc_col) || is.na(p_col)) stop('Required columns not found. Expected log2FC/logFC and padj/FDR/pvalue.')
fc <- suppressWarnings(as.numeric(data[[fc_col]])); p <- suppressWarnings(as.numeric(data[[p_col]]))
keep <- is.finite(fc) & is.finite(p); data <- data[keep,,drop=FALSE]; fc <- fc[keep]; p <- p[keep]
p[p<=0] <- min(p[p>0], na.rm=TRUE)/10
sig <- p < 0.05 & abs(fc) >= 1
color <- ifelse(sig & fc>0, '#dc2626', ifelse(sig & fc<0, '#2563eb', '#94a3b8'))

png(file.path(out,'volcano.png'), width=1400, height=1050, res=160)
par(mar=c(5,5,3,2))
plot(fc, -log10(p), pch=19, cex=.72, col=color, xlab='log2 fold change', ylab='-log10(P value)', main='RNA-seq Volcano Plot')
abline(v=c(-1,1), h=-log10(0.05), lty=2, col='#64748b')
legend('topright', legend=c('Up','Down','Not significant'), col=c('#dc2626','#2563eb','#94a3b8'), pch=19, bty='n')
label <- if(ncol(data)) as.character(data[[1]]) else seq_along(fc)
top <- head(order(p),10)
text(fc[top], -log10(p[top]), labels=label[top], pos=3, cex=.65)
dev.off()

result <- data.frame(Gene=label, log2FC=fc, PValue=p, Significant=sig)
write.csv(result, file.path(out,'volcano_data.csv'), row.names=FALSE)
writeLines(c(paste('Input:',file),paste('Rows:',nrow(result)),paste('Significant:',sum(sig))), file.path(out,'result.txt'))