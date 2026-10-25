args <- commandArgs(FALSE)
script <- sub('^--file=', '', args[grepl('^--file=', args)])
root <- dirname(dirname(normalizePath(script)))
Sys.setenv(KNHANES_LOCAL_SITE=file.path(root,'site'))
setwd(file.path(root,'src'))
e <- new.env(parent=globalenv())
suppressPackageStartupMessages(sys.source('app.R',envir=e))
original <- file.path(dirname(root),'04_源码网站')
stopifnot(identical(readRDS('data/atlas.rds'), readRDS(file.path(original,'data/atlas.rds'))))
stopifnot(identical(readRDS('data/voe/summary.rds'), readRDS(file.path(original,'data/voe/summary.rds'))))
s <- e$voe_summary
cases <- unique(c(1L, match('diet_freq63_beer::p_ggt',s$pair_id),
  which(s$transform=='categorical')[1],which(s$exposure_id=='e_education')[1],
  which(s$models_fitted<s$models_planned)[1],nrow(s)))
for(i in cases) for(kind in c('models','terms','drivers')) {
  x <- s[i,]
  index <- e$voe[[switch(kind,models='model_index',terms='term_index',drivers='driver_index')]]
  row <- index[index$pair_id==x$pair_id,,drop=FALSE]
  expected <- fst::read_fst(file.path(original,'data/voe',paste0(kind,'.fst')),from=row$first,to=row$last)
  contrast <- if(kind=='models') NULL else x$contrast_id
  if(!is.null(contrast)) expected <- expected[expected$contrast_id==contrast,,drop=FALSE]
  rownames(expected) <- NULL
  stopifnot(identical(e$voe_read(kind,x$pair_id,contrast),expected))
}
core <- c('by_phenotype_manhattan_plot','by_phenotype_effect_size','by_phenotype_r2_plot',
  'by_phenotype_volcano_plot','by_phenotype_globe_plot','by_phenotype_estimate_plot',
  'by_exposure_volcano_plot','by_exposure_context_plot','by_exposure_r2_plot','by_exposure_estimate_plot',
  'by_exposure_group_volcano_plot','by_exposure_group_context_plot','by_exposure_group_r2_plot','by_exposure_group_estimate_plot',
  'by_phenotype_table','by_exposure_table','by_exposure_group_table','exposure_corr_table','phenotype_corr_table',
  'e_catalog_table','p_catalog_table','figure_preview','joint_table')
voe <- c('voe_pair_title','voe_contrast_text','voe_pair_stats','voe_sample_note',
  'voe_scatter','voe_driver_plot','voe_specification_plot','voe_model_table','voe_summary_table',
  'voe_range_plot','voe_retention_plot','voe_overview_table','voe_results_title')
shiny::testServer(e$server, {
  session$setInputs(pvarname='p_bmi',evarname='e_blood_mercury',egroup='Environmental chemicals',figure='1',
    atlas_site_url='http://127.0.0.1:8848/knhanes_atlas/',atlas_url_search='',
    voe_phenotype='p_ggt',voe_exposure='diet_freq63_beer',voe_contrast='continuous',voe_factor='edu_analysis')
  for(id in c(core,voe)) stopifnot(!is.null(output[[id]]))
  for(i in cases) {
    x <- s[i,]
    d <- e$voe_read('drivers',x$pair_id,x$contrast_id)
    f <- d$factor[which(is.finite(d$change_in_absolute_beta))[1]]
    if(is.na(f)) f <- names(e$voe$factors)[1]
    session$setInputs(voe_phenotype=x$phenotype_id,voe_exposure=x$exposure_id,
      voe_contrast=x$contrast_id,voe_factor=f)
    downloaded <- read.csv(output$voe_models_download,check.names=FALSE)
    stopifnot(nrow(downloaded)==x$models_planned,all(downloaded$contrast_id==x$contrast_id),
      sum(is.finite(downloaded$beta))==x$n_models)
  }
})
jsonlite::write_json(list(unchanged_atlas=TRUE,unchanged_voe_summary=TRUE,
  reader_cases=length(cases)*3L,outputs=c(core,voe),downloads=length(cases)),
  file.path(root,'checks/r_checks.json'),auto_unbox=TRUE,pretty=TRUE)
cat('Verified',length(core)+length(voe),'outputs and',length(cases),'VoE cases.\n')
