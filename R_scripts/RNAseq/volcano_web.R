args <- commandArgs(trailingOnly = TRUE)

if(length(args) < 2){
  stop('Usage: Rscript volcano_web.R input output')
}

input <- args[1]
out <- args[2]

dir.create(out, recursive=TRUE, showWarnings=FALSE)

png(file.path(out,'volcano.png'), width=1200, height=900, res=150)
plot(1:10, 1:10, main='RNA-seq Volcano Plot Template', xlab='log2FC', ylab='-log10(P value)')
dev.off()

writeLines('volcano analysis finished', file.path(out,'result.txt'))
