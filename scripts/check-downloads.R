args <- commandArgs(FALSE)
root <- dirname(dirname(normalizePath(sub('^--file=','',args[grepl('^--file=',args)]))))
Sys.setenv(KNHANES_LOCAL_SITE=file.path(root,'site'))
setwd(file.path(root,'src'))
e <- new.env(parent=globalenv())
suppressPackageStartupMessages(sys.source('app.R',envir=e))
check_dir <- file.path(root,Sys.getenv('ATLAS_CHECK_DIR','checks'))
report <- jsonlite::fromJSON(file.path(check_dir,'browser-check.json'))
cases <- jsonlite::fromJSON(file.path(root,'checks/cases.json'))
checks <- list()
compare <- function(label,expected) {
  file <- report$downloads$file[report$downloads$label==label]
  stopifnot(length(file)==1)
  actual <- read.csv(file,check.names=FALSE,stringsAsFactors=FALSE,na.strings='')
  target <- tempfile(fileext='.csv')
  e$write_summary_csv(expected,target)
  expected <- read.csv(target,check.names=FALSE,stringsAsFactors=FALSE,na.strings='')
  unlink(target)
  stopifnot(identical(names(actual),names(expected)),nrow(actual)==nrow(expected))
  for(name in names(expected)) {
    a <- actual[[name]]; b <- expected[[name]]
    stopifnot(identical(is.na(a),is.na(b)))
    if(is.numeric(a)&&is.numeric(b)) {
      stopifnot(isTRUE(all.equal(a,b,tolerance=1e-13,check.attributes=FALSE)))
    } else stopifnot(identical(a,b))
  }
  checks[[label]] <<- list(rows=nrow(actual),columns=ncol(actual),all_fields_match=TRUE)
}
compare('phenotype',e$reactable_tibble(dplyr::filter(e$adjusted_meta_2,pvarname=='p_bmi')))
compare('exposure',e$reactable_tibble(dplyr::filter(e$adjusted_meta_2,evarname=='e_blood_mercury')))
compare('group',e$reactable_tibble(dplyr::filter(e$adjusted_meta_2,ecategory=='Environmental chemicals')))
shiny::testServer(e$server, {
  for(label in c('default','categorical','education','failed')) {
    x <- cases[[label]]
    d <- e$voe_read('drivers',x$pair_id,x$contrast_id)
    f <- d$factor[which(is.finite(d$change_in_absolute_beta))[1]]
    session$setInputs(voe_phenotype=x$phenotype_id,voe_exposure=x$exposure_id,
      voe_contrast=x$contrast_id,voe_factor=f,
      atlas_site_url='http://127.0.0.1:8848/knhanes_atlas/',atlas_url_search='')
    compare(paste0('voe_',label),read.csv(output$voe_models_download,check.names=FALSE,na.strings=''))
    if(label=='default') {
      compare('voe_drivers',read.csv(output$voe_drivers_download,check.names=FALSE,na.strings=''))
      compare('voe_summary',read.csv(output$voe_summary_download,check.names=FALSE,na.strings=''))
    }
  }
})
jsonlite::write_json(checks,file.path(check_dir,'download_parity.json'),auto_unbox=TRUE,pretty=TRUE)
cat('All',length(checks),'browser CSV downloads match native R results.\n')
