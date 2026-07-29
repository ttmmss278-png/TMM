args <- commandArgs(trailingOnly = TRUE)

if(length(args) < 2){
  stop('Usage: Rscript bubble_web.R input output')
}

out <- args[2]
dir.create(out, recursive=TRUE, showWarnings=FALSE)

png(file.path(out,'bubble.png'), width=1200, height=900, res=150)
plot(1:10,1:10, main='Enrichment Bubble Plot Template', xlab='Gene ratio', ylab='Pathway')
dev.off()

writeLines('bubble analysis finished', file.path(out,'result.txt'))
