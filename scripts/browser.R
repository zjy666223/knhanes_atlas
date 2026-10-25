# Browser deployment reads the same result rows from one phenotype chunk at a time.
.voe_cache <- new.env(parent=emptyenv())
.voe_cache$phenotype <- NULL
voe_read <- function(kind, pair, contrast=NULL) {
  phenotype <- voe_summary$phenotype_id[match(pair, voe_summary$pair_id)]
  stopifnot(length(phenotype)==1L, !is.na(phenotype), kind %in% c('models','terms','drivers'))
  if (!identical(.voe_cache$phenotype, phenotype)) {
    local_site <- Sys.getenv('KNHANES_LOCAL_SITE')
    if (nzchar(local_site)) {
      path <- file.path(local_site, 'data/voe', paste0(phenotype,'.rds'))
      chunk <- readRDS(path)
    } else {
      base <- shiny::getDefaultReactiveDomain()$input$atlas_site_url
      shiny::req(!is.null(base), nzchar(base))
      path <- tempfile(fileext='.rds')
      on.exit(unlink(path), add=TRUE)
      utils::download.file(paste0(base, 'data/voe/', phenotype, '.rds'), path,
        mode='wb', quiet=TRUE)
      chunk <- readRDS(path)
    }
    .voe_cache$data <- chunk
    .voe_cache$phenotype <- phenotype
  }
  x <- .voe_cache$data[[kind]]
  x <- x[x$pair_id==pair,,drop=FALSE]
  if (!is.null(contrast)) x <- x[x$contrast_id==contrast,,drop=FALSE]
  rownames(x) <- NULL
  x
}
