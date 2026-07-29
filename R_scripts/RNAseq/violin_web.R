args <- commandArgs(trailingOnly = TRUE)

if(length(args) < 2){
  stop('Usage: Rscript violin_web.R input output')
}

input <- args[1]
out <- args[2]

dir.create(out, recursive=TRUE, showWarnings=FALSE)

png(file.path(out,'violin.png'), width=1200, height=900, res=150)
boxplot(1:10, main='Gene Expression Violin Plot Template')
dev.off()

writeLines('violin analysis finished', file.path(out,'result.txt'))
