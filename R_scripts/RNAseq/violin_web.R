args <- commandArgs(trailingOnly = TRUE)
if(length(args) < 2) stop('Usage: Rscript violin_web.R input output [genes] [title] [scale]')
input <- args[1]; out <- args[2]
gene_text <- if(length(args)>=3) args[3] else ''
plot_title <- if(length(args)>=4 && nzchar(args[4])) args[4] else 'Gene Expression Violin Plot'
scale_mode <- if(length(args)>=5) args[5] else 'none'
dir.create(out, recursive=TRUE, showWarnings=FALSE)

read_auto <- function(file){
  if(grepl('\\.csv$', file, ignore.case=TRUE)) read.csv(file, check.names=FALSE, stringsAsFactors=FALSE)
  else if(grepl('\\.(tsv|txt)$', file, ignore.case=TRUE)) read.delim(file, check.names=FALSE, stringsAsFactors=FALSE)
  else stop('Please export the expression matrix as CSV, TSV or TXT before analysis.')
}

data <- read_auto(input)
if(ncol(data)<2) stop('Expression matrix must contain Gene ID and sample columns.')
all_genes <- as.character(data[[1]])
requested <- unique(Filter(nzchar, unlist(strsplit(gene_text, '[,;[:space:]]+'))))
if(!length(requested)) stop('No Gene ID was provided.')
indices <- match(toupper(requested), toupper(all_genes))
found <- !is.na(indices)
if(!any(found)) stop('None of the requested genes were found in the first column.')
selected_genes <- requested[found]
mat <- as.matrix(data[indices[found],-1,drop=FALSE]); storage.mode(mat) <- 'numeric'; rownames(mat) <- selected_genes
mat[!is.finite(mat)] <- NA
if(scale_mode=='log2') mat <- log2(pmax(mat,0)+1)
if(scale_mode=='zscore'){
  mat <- t(scale(t(mat))); mat[!is.finite(mat)] <- 0
}

values <- as.numeric(mat); values <- values[is.finite(values)]
if(!length(values)) stop('Selected rows contain no numeric expression values.')
ylim <- range(values); if(diff(ylim)==0) ylim <- ylim + c(-1,1)

png(file.path(out,'violin.png'), width=max(1200,350*nrow(mat)), height=950, res=160)
par(mar=c(7,5,4,2))
plot(NA, xlim=c(.4,nrow(mat)+.6), ylim=ylim, xaxt='n', xlab='', ylab='Expression', main=plot_title)
axis(1, at=seq_len(nrow(mat)), labels=rownames(mat), las=2, cex.axis=.8)
abline(h=pretty(ylim), col='#e2e8f0', lty=1)
for(i in seq_len(nrow(mat))){
  x <- as.numeric(mat[i,]); x <- x[is.finite(x)]
  if(length(unique(x))>1 && length(x)>2){
    d <- density(x, na.rm=TRUE)
    width <- d$y/max(d$y)*.36
    polygon(c(i-width, rev(i+width)), c(d$x, rev(d$x)), col='#93c5fd', border='#2563eb')
  }
  points(rep(i,length(x))+runif(length(x),-.035,.035), x, pch=16, cex=.55, col='#1e3a8a80')
  segments(i-.18, median(x), i+.18, median(x), lwd=2, col='#dc2626')
}
dev.off()

write.csv(cbind(Gene=rownames(mat),as.data.frame(mat,check.names=FALSE)), file.path(out,'violin_selected_expression.csv'), row.names=FALSE)
missing <- requested[!found]
writeLines(c(paste('Input:',input),paste('Genes plotted:',paste(selected_genes,collapse=', ')),if(length(missing)) paste('Genes not found:',paste(missing,collapse=', ')) else 'All requested genes were found.'), file.path(out,'result.txt'))