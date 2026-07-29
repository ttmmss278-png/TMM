args <- commandArgs(trailingOnly = TRUE)
if(length(args) < 2) stop('Usage: Rscript bubble_web.R input output')
input <- args[1]; out <- args[2]
dir.create(out, recursive=TRUE, showWarnings=FALSE)

pick_file <- function(path){
  if(file.exists(path) && !isTRUE(file.info(path)$isdir)) return(path)
  files <- list.files(path, recursive=TRUE, full.names=TRUE)
  files <- files[grepl('\\.(csv|tsv|txt)$', files, ignore.case=TRUE)]
  hit <- files[grepl('kegg|go|enrich|pathway', basename(files), ignore.case=TRUE)]
  if(length(hit)) hit[1] else if(length(files)) files[1] else stop('No enrichment file found')
}
read_auto <- function(file){
  if(grepl('\\.csv$', file, ignore.case=TRUE)) read.csv(file, check.names=FALSE, stringsAsFactors=FALSE)
  else read.delim(file, check.names=FALSE, stringsAsFactors=FALSE)
}
find_col <- function(names, candidates){
  normal <- gsub('[^a-z0-9]','',tolower(names)); idx <- match(candidates, normal, nomatch=0); idx <- idx[idx>0]
  if(length(idx)) idx[1] else NA_integer_
}
ratio_value <- function(x){
  x <- as.character(x)
  out <- suppressWarnings(as.numeric(x))
  fraction <- grepl('/',x)
  if(any(fraction)) out[fraction] <- sapply(strsplit(x[fraction],'/'), function(v) as.numeric(v[1])/as.numeric(v[2]))
  out
}

file <- pick_file(input); data <- read_auto(file)
term_col <- find_col(names(data), c('description','term','pathway','category','id'))
ratio_col <- find_col(names(data), c('generatio','richfactor','ratio'))
count_col <- find_col(names(data), c('count','genecount','size'))
p_col <- find_col(names(data), c('padjust','padj','fdr','pvalue','pval'))
if(is.na(term_col) || is.na(p_col)) stop('Required enrichment columns not found. Expected Description/Term and p.adjust/pvalue.')
term <- as.character(data[[term_col]])
p <- suppressWarnings(as.numeric(data[[p_col]]))
ratio <- if(!is.na(ratio_col)) ratio_value(data[[ratio_col]]) else seq_along(term)/length(term)
count <- if(!is.na(count_col)) suppressWarnings(as.numeric(data[[count_col]])) else rep(1,length(term))
keep <- is.finite(p) & is.finite(ratio) & is.finite(count)
term <- term[keep]; p <- p[keep]; ratio <- ratio[keep]; count <- count[keep]
order_id <- head(order(p),20); term <- term[order_id]; p <- p[order_id]; ratio <- ratio[order_id]; count <- count[order_id]
order_id <- order(ratio); term <- term[order_id]; p <- p[order_id]; ratio <- ratio[order_id]; count <- count[order_id]
size <- 1.5 + 4.5*(count-min(count))/(max(count)-min(count)+1e-9)
palette <- colorRampPalette(c('#2563eb','#f59e0b','#dc2626'))(100)
color_index <- cut(-log10(pmax(p,1e-300)), breaks=100, labels=FALSE, include.lowest=TRUE)

png(file.path(out,'bubble.png'), width=1500, height=1100, res=160)
par(mar=c(5,14,3,2))
plot(ratio, seq_along(term), pch=21, cex=size, bg=palette[color_index], col='#475569', yaxt='n', xlab='Gene ratio / Rich factor', ylab='', main='GO / KEGG Enrichment Bubble Plot')
axis(2, at=seq_along(term), labels=term, las=2, cex.axis=.75)
grid(nx=NA, ny=NULL, col='#e2e8f0')
dev.off()

write.csv(data.frame(Term=term,Ratio=ratio,Count=count,PValue=p), file.path(out,'bubble_data.csv'), row.names=FALSE)
writeLines(c(paste('Input:',file),paste('Terms plotted:',length(term))), file.path(out,'result.txt'))