# Convert stored study results into browser-readable R files. No model fitting.
args <- commandArgs(FALSE)
script <- sub('^--file=', '', args[grepl('^--file=', args)])
root <- dirname(dirname(normalizePath(script)))
project <- dirname(root)
original <- file.path(project, '04_源码网站')
src <- file.path(root, 'src')
site <- file.path(root, 'site')
for (d in c('R', 'www', 'data/voe')) dir.create(file.path(src, d), recursive=TRUE, showWarnings=FALSE)
for (d in c('data/voe', 'research/data', 'research/figures')) dir.create(file.path(site, d), recursive=TRUE, showWarnings=FALSE)
files <- c('app.R', 'R/data.R', 'R/style.R', 'R/vibration.R', 'www/study.css', 'data/atlas.rds', 'data/voe/summary.rds', 'LICENSE.md')
stopifnot(all(file.copy(file.path(original, files), file.path(src, files), overwrite=TRUE)))

app <- paste(readLines(file.path(src, 'app.R'), warn=FALSE), collapse='\n')
app <- sub('library(tidyverse)', 'library(dplyr)\nlibrary(tidyr)\nlibrary(forcats)\nlibrary(ggplot2)\nlibrary(stringr)', app, fixed=TRUE)
app <- gsub('library(fst)\n', '', app, fixed=TRUE)
app <- gsub('library(gplots)\n', '', app, fixed=TRUE)
app <- gsub('library(ggrepel)\n', '', app, fixed=TRUE)
app <- sub('shiny::addResourcePath("research", normalizePath("../01_网站"))', '', app, fixed=TRUE)
app <- gsub('../01_网站/data/', 'data/', app, fixed=TRUE)
app <- sub('source("R/vibration.R", local=TRUE)', 'source("R/vibration.R", local=TRUE)\nsource("R/browser.R", local=TRUE)', app, fixed=TRUE)
app <- sub('ui <- tagList(tags$head(includeCSS("www/study.css")), ui)',
  'ui <- tagList(tags$head(includeCSS("www/study.css")), includeScript("www/browser.js"), ui)', app, fixed=TRUE)
app <- sub('parseQueryString(session$clientData$url_search)', 'parseQueryString(input$atlas_url_search)', app, fixed=TRUE)
app <- sub('bindEvent(session$clientData$url_search, once = TRUE)', 'bindEvent(input$atlas_url_search, once = TRUE)', app, fixed=TRUE)
app <- gsub('base_url <- paste0\\(session\\$clientData\\$url_protocol,[\\s\\S]*?session\\$clientData\\$url_pathname\\)',
  'base_url <- input$atlas_site_url', app, perl=TRUE)
app <- gsub('img(src=', 'img(`data-atlas-src`=', app, fixed=TRUE)
writeLines(app, file.path(src, 'app.R'))
stopifnot(file.copy(file.path(root,'scripts/browser.R'), file.path(src,'R/browser.R'), overwrite=TRUE))
stopifnot(file.copy(file.path(root,'scripts/browser.js'), file.path(src,'www/browser.js'), overwrite=TRUE))

vibration <- paste(readLines(file.path(src, 'R/vibration.R'), warn=FALSE), collapse='\n')
vibration <- sub('fst::threads_fst(1L)\n', '', vibration, fixed=TRUE)
# Replace only the storage reader; all plotting, ranking and downloads stay in R.
start <- regexpr('voe_read <- function(', vibration, fixed=TRUE)[1]
end <- regexpr('voe_theme <- function()', vibration, fixed=TRUE)[1]
stopifnot(start>0L, end>start)
vibration <- paste0(substr(vibration, 1L, start-1L), substr(vibration, end, nchar(vibration)))
writeLines(vibration, file.path(src, 'R/vibration.R'))

for (name in c('figures.json', 'joint.csv')) {
  stopifnot(file.copy(file.path(project, '01_网站/data', name), file.path(src, 'data', name), overwrite=TRUE))
}
for (name in c('associations','exposures','phenotypes','joint','network','exposure_profiles','phenotype_profiles','vibration')) {
  stopifnot(file.copy(file.path(project, '01_网站/data', paste0(name,'.csv')),
    file.path(site, 'research/data', paste0(name,'.csv')), overwrite=TRUE))
}
figures <- list.files(file.path(project, '01_网站/figures'), full.names=TRUE)
figures <- figures[!startsWith(basename(figures), '.')]
stopifnot(all(file.copy(figures, file.path(site, 'research/figures'), overwrite=TRUE)))

fst::threads_fst(1L)
summary <- readRDS(file.path(original, 'data/voe/summary.rds'))
sources <- lapply(c('models','terms','drivers'), function(kind) {
  fst::read_fst(file.path(original, 'data/voe', paste0(kind,'.fst')))
})
names(sources) <- c('models','terms','drivers')
pair_phenotype <- unique(summary$summary[c('pair_id','phenotype_id')])
stopifnot(!anyDuplicated(pair_phenotype$pair_id))
groups <- lapply(sources, function(d) {
  pheno <- pair_phenotype$phenotype_id[match(d$pair_id, pair_phenotype$pair_id)]
  stopifnot(!anyNA(pheno))
  split(seq_len(nrow(d)), pheno)
})
phenotypes <- sort(unique(pair_phenotype$phenotype_id))
rows <- setNames(integer(3), names(sources))
sizes <- numeric(length(phenotypes))
for (i in seq_along(phenotypes)) {
  id <- phenotypes[i]
  chunk <- lapply(names(sources), function(kind) sources[[kind]][groups[[kind]][[id]],,drop=FALSE])
  names(chunk) <- names(sources)
  path <- file.path(site, 'data/voe', paste0(id,'.rds'))
  saveRDS(chunk, path, compress='gzip', version=3)
  restored <- readRDS(path)
  stopifnot(identical(chunk, restored))
  rows <- rows + vapply(chunk, nrow, integer(1))
  sizes[i] <- file.info(path)$size
  if (i %% 20L == 0L || i==length(phenotypes)) cat('Verified phenotype files:', i, '/', length(phenotypes), '\n')
}
stopifnot(identical(unname(rows), unname(vapply(sources, nrow, integer(1)))))
jsonlite::write_json(list(phenotypes=length(phenotypes), rows=as.list(rows),
  models_fitted=sum(sources$models$status=='ok'),
  exact_RDS_roundtrip=TRUE, total_bytes=sum(sizes), largest_file_bytes=max(sizes),
  original_hashes=as.list(tools::md5sum(file.path(original, files)))),
  file.path(root,'checks/data_conversion.json'), pretty=TRUE, auto_unbox=TRUE)
cat('Data conversion complete; all records preserved.\n')
