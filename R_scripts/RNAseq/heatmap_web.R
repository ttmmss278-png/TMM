args <- commandArgs(trailingOnly = TRUE)

if(length(args) < 2){
  stop('Usage: Rscript heatmap_web.R input output')
}

out <- args[2]
dir.create(out, recursive=TRUE, showWarnings=FALSE)

png(file.path(out,'heatmap.png'), width=1200, height=900, res=150)
heatmap(matrix(1:100,10,10), main='Expression Heatmap Template')
dev.off()

writeLines('heatmap analysis finished', file.path(out,'result.txt'))
