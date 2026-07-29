args <- commandArgs(trailingOnly = TRUE)
if(length(args) < 2) stop('Usage: Rscript heatmap_web.R input output')
input <- args[1]; out <- args[2]
dir.create(out, recursive=TRUE, showWarnings=FALSE)

pick_file <- function(path){
  if(file.exists(path) && !isTRUE(file.info(path)$isdir)) return(path)
  files <- list.files(path, recursive=TRUE, full.names=TRUE)
  files <- files[grepl('\\.(csv|tsv|txt)$', files, ignore.case=TRUE)]
  hit <- files[grepl('tpm|fpkm|count|expression|matrix', basename(files), ignore.case=TRUE)]
  if(length(hit)) hit[1] else if(length(files)) files[1] else stop('No expression matrix found')
}
read_auto <- function(file){
  if(grepl('\\.csv$', file, ignore.case=TRUE)) read.csv(file, check.names=FALSE, stringsAsFactors=FALSE)
  else read.delim(file, check.names=FALSE, stringsAsFactors=FALSE)
}

file <- pick_file(input); data <- read_auto(file)
if(ncol(data) < 3) stop('Expression matrix must contain a Gene ID column and at least two sample columns.')
genes <- make.unique(as.character(data[[1]]))
mat <- as.matrix(data[,-1,drop=FALSE]); storage.mode(mat) <- 'numeric'; rownames(mat) <- genes
mat <- mat[rowSums(is.finite(mat)) == ncol(mat),,drop=FALSE]
if(!nrow(mat)) stop('No numeric expression rows were found.')
if(all(mat >= 0, na.rm=TRUE)) mat <- log2(mat + 1)
variances <- apply(mat,1,var,na.rm=TRUE)
selected <- head(order(variances,decreasing=TRUE), min(40,length(variances)))
mat <- mat[selected,,drop=FALSE]
scaled <- t(scale(t(mat))); scaled[!is.finite(scaled)] <- 0

png(file.path(out,'heatmap.png'), width=1500, height=1200, res=160)
par(mar=c(5,5,3,2))
heatmap(scaled, scale='none', col=colorRampPalette(c('#2563eb','#ffffff','#dc2626'))(120), margins=c(8,10), main='Top Variable Genes Expression Heatmap')
dev.off()

write.csv(mat, file.path(out,'heatmap_selected_expression.csv'))
writeLines(c(paste('Input:',file),paste('Genes plotted:',nrow(mat)),paste('Samples:',ncol(mat))), file.path(out,'result.txt'))