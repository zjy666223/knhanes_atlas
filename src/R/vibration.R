# The browser reads the completed ZJR results, one pair at a time.
voe <- readRDS('data/voe/summary.rds')
voe_colors <- c('Atlas Bonferroni-significant'='#B4604C', 'Other coefficients'='#A5AFB8')
voe_summary <- voe$summary |>
  dplyr::mutate(group=ifelse(atlas_significant, names(voe_colors)[1], names(voe_colors)[2]))

voe_theme <- function() {
  study_theme()
}
voe_percent <- function(x) sprintf('%.1f%%',100*x)

vibration_ui <- function() {
  first <- unique(voe_summary[voe_summary$phenotype_id=='p_ggt', c('exposure_id','exposure')])
  tabPanel('Vibration of effects',
    sidebarPanel(width=3,
      h3('By association'),
      selectInput('voe_phenotype','Phenotype', choices=setNames(p_variables$pvarname,
        p_variables$pvardesc_selector), selected='p_ggt'),
      selectInput('voe_exposure','Exposure', choices=setNames(first$exposure_id,
        first$exposure), selected='diet_freq63_beer'),
      selectInput('voe_contrast','Coefficient contrast',choices=c('Per SD of log10 exposure'='continuous')),
      selectInput('voe_factor','Highlight adjustment for',choices=setNames(names(voe$factors),
        unname(voe$factors)), selected='edu_analysis'),
      downloadButton('voe_models_download','Download model estimates'), br(), br(),
      downloadButton('voe_drivers_download','Download covariate contributions'),
      hr(), a('Download Extended Data Figure 4',
        href='research/figures/11_效应振动.pdf',download='Figure Extended 4_v1.pdf'),
      br(), br(), a('Download all VoE summaries',href='research/data/vibration.csv',
        download='vibration.csv')
    ),
    mainPanel(width=9,
      div(class='voe-heading',h1('Vibration of effects'),h3(textOutput('voe_pair_title'))),
      tabsetPanel(id='voe_tabs',
        tabPanel('Association explorer',
          div(class='voe-plots',fluidRow(column(6,plotOutput('voe_scatter',height='430px')),
                   column(6,plotOutput('voe_driver_plot',height='430px'))))
        ),
        tabPanel('Model specifications',plotOutput('voe_specification_plot',height='680px')),
        tabPanel('Results',
          h3('Association summary'),textOutput('voe_contrast_text'),uiOutput('voe_pair_stats'),
          uiOutput('voe_sample_note'),
          h3('Model estimates'),reactableOutput('voe_model_table'),
          h3(textOutput('voe_results_title')),
          downloadButton('voe_summary_download','Download phenotype results'),br(),br(),
          reactableOutput('voe_summary_table')
        ),
        tabPanel('Atlas overview',
          p('24,008 exposure–phenotype pairs · 26,078 coefficient contrasts · 1,535,744 fitted models'),
          p('Groups are defined by Bonferroni significance in the original atlas. These panels summarize all coefficient contrasts.'),
          div(class='voe-plots',fluidRow(column(6,plotOutput('voe_range_plot',height='420px')),
                   column(6,plotOutput('voe_retention_plot',height='420px')))),
          reactableOutput('voe_overview_table')
        ),
        tabPanel('Methods',
          h3('Adjustment specifications'),
          p('All models retain age, age squared, sex, survey year and applicable total-energy or urinary-creatinine adjustment. Up to 64 unique specifications per pair vary 12 optional categorical factors: education, household income, smoking, drinking frequency, walking, muscle-strengthening exercise, perceived stress, occupation, household size, urban/rural residence, home ownership and housing type.'),
          p('Complementary sampling selects up to 64 unique specifications, balances inclusion of each eligible factor and includes the primary specification, no optional factors and all eligible optional factors. Factors equivalent to the target exposure are excluded from the optional set.'),
          h3('Samples and coefficient scales'),
          p('Within each pair, all specifications use the same complete-case participants, survey weights, strata, primary sampling units, transformations and categorical references. The primary model is re-estimated in this common sample; its coefficient can differ from the original atlas coefficient because the eligible sample changes.'),
          p('Continuous exposures are expressed per standard deviation of log10 exposure, ordinal exposures per score increment, and categorical exposures relative to their original reference. Phenotypes are standardized. In the model-specification plot, estimates and their model-specific 95% confidence intervals are ordered by the coefficient; the matrix below records the optional factors included in each model.'),
          h3('Robustness measures'),
          p('Nominal retention is the fraction of estimable specifications with P < 0.05. Bonferroni retention uses the fixed original threshold P < 0.05 / 26,078. A sign reversal requires both positive and negative coefficients; significant opposite directions additionally require P < 0.05 in both directions.'),
          p('Of 1,536,512 evaluated specifications, 1,535,744 produced fitted results. Unsuccessful specifications remain in the model download with their recorded status and reason; retention denominators count estimable coefficients.'),
          h3('Covariate contributions'),
          p('Contributions are the coefficients from an equally weighted linear model of absolute exposure coefficients against covariate-inclusion indicators. Negative values indicate attenuation and positive values indicate amplification. Bars display estimable contributions; unavailable contributions remain recorded in the download.')
        )
      )
    )
  )
}

vibration_server <- function(input, output, session) {
  phenotype_rows <- reactive({
    req(input$voe_phenotype)
    voe_summary[voe_summary$phenotype_id==input$voe_phenotype, , drop=FALSE]
  })
  observeEvent(input$voe_phenotype, {
    x <- unique(phenotype_rows()[c('exposure_id','exposure')])
    current <- isolate(input$voe_exposure)
    selected <- if (!is.null(current) && current %in% x$exposure_id) current else x$exposure_id[1]
    updateSelectInput(session,'voe_exposure',choices=setNames(x$exposure_id,x$exposure),selected=selected)
  })
  pair_rows <- reactive({
    req(input$voe_exposure)
    x <- phenotype_rows()
    x[x$exposure_id==input$voe_exposure, , drop=FALSE]
  })
  observeEvent(pair_rows(), {
    x <- pair_rows(); req(nrow(x)>0)
    current <- isolate(input$voe_contrast)
    selected <- if (!is.null(current) && current %in% x$contrast_id) current else x$contrast_id[1]
    updateSelectInput(session,'voe_contrast',choices=setNames(x$contrast_id,x$contrast_label),selected=selected)
  })
  chosen <- reactive({
    req(input$voe_contrast)
    x <- pair_rows(); x <- x[x$contrast_id==input$voe_contrast, , drop=FALSE]
    req(nrow(x)==1L); x
  })
  models <- reactive({
    x <- chosen()
    m <- voe_read('models',x$pair_id)
    t <- voe_read('terms',x$pair_id,x$contrast_id)
    d <- merge(m,t,by=c('pair_id','model_id'),all.x=TRUE,sort=FALSE)
    d$contrast_id <- x$contrast_id
    d$contrast_label <- x$contrast_label
    d$level_label <- x$level
    d$reference_label <- x$reference
    d$minus_log10_p <- -d$log_p_value/log(10)
    valid <- which(is.finite(d$beta) & is.finite(d$minus_log10_p))
    ranked <- valid[order(d$beta[valid],d$model_id[valid])]
    d$model_rank <- NA_integer_
    d$model_rank[ranked] <- seq_along(ranked)
    d
  })
  contributions <- reactive({
    x <- chosen(); voe_read('drivers',x$pair_id,x$contrast_id)
  })
  observeEvent(contributions(), {
    d <- contributions()
    available <- intersect(names(voe$factors),d$factor[is.finite(d$change_in_absolute_beta)])
    if (!length(available)) available <- names(voe$factors)
    current <- isolate(input$voe_factor)
    selected <- if (!is.null(current) && current %in% available) current else available[1]
    updateSelectInput(session,'voe_factor',choices=setNames(available,unname(voe$factors[available])),selected=selected)
  })
  output$voe_pair_title <- renderText({
    x <- chosen(); paste(x$phenotype, '~', x$exposure)
  })
  output$voe_contrast_text <- renderText(chosen()$contrast_label)
  output$voe_pair_stats <- renderUI({
    x <- chosen()
    values <- c('Estimable models'=paste0(x$n_models,' / ',x$models_planned),
      'Common N'=format(x$n_voe,big.mark=',',scientific=FALSE),
      'P < 0.05'=voe_percent(x$nominal_retention),
      'Bonferroni'=voe_percent(x$original_bonferroni_retention),
      'Positive β'=voe_percent(x$positive_fraction),
      'Sign reversal'=ifelse(x$sign_reversal,'Yes','No'),
      'Significant opposite directions'=ifelse(x$significant_opposite_signs,'Yes','No'))
    div(class='study-table-wrap',tags$table(class='study-table',
      tags$thead(tags$tr(lapply(names(values),tags$th))),
      tags$tbody(tags$tr(lapply(unname(values),tags$td)))))
  })
  output$voe_sample_note <- renderUI({
    x <- chosen()
    div(class='study-table-wrap',tags$table(class='study-table',
      tags$thead(tags$tr(tags$th('Analysis'),tags$th('N'),tags$th('β'))),
      tags$tbody(
        tags$tr(tags$td('Original atlas'),tags$td(format(x$n_atlas,big.mark=',')),
          tags$td(sprintf('%.4f',x$original_beta))),
        tags$tr(tags$td('Primary model · common VoE sample'),tags$td(format(x$n_voe,big.mark=',')),
          tags$td(sprintf('%.4f',x$primary_beta))))))
  })
  plot_models <- reactive({
    req(input$voe_factor %in% names(voe$factors))
    d <- models() |> filter(!is.na(model_rank)) |> arrange(model_rank)
    validate(need(nrow(d)>0,'No estimable coefficients for this selection.'))
    d$included <- factor(ifelse(grepl(paste0('\\b',input$voe_factor,'\\b'),d$covariates),
      'Included','Not included'),levels=c('Included','Not included'))
    d$rank <- d$model_rank
    d
  })
  output$voe_scatter <- renderPlot({
    d <- plot_models()
    ggplot(d,aes(beta,minus_log10_p)) +
      geom_vline(xintercept=0,color='#A5AFB8',linewidth=.4,linetype=3) +
      geom_hline(yintercept=-log10(c(.05,.05/26078)),color='#7D8991',linetype=c(2,3),linewidth=.4) +
      geom_point(aes(color=included),size=2.5,alpha=.9) +
      geom_point(data=d[d$model_id=='primary',],aes(shape='Primary model'),
        fill='white',color=study_colors[['ink']],size=3,stroke=.8) +
      annotate('text',x=Inf,y=-log10(c(.05,.05/26078)),
        label=c('P = 0.05','Bonferroni'),hjust=1.08,vjust=-.6,size=3.2,color=study_colors[['ink']]) +
      scale_color_manual(values=c('Included'='#417D95','Not included'='#C5A265'),drop=FALSE) +
      scale_shape_manual(values=c('Primary model'=23)) +
      scale_y_continuous(expand=expansion(mult=c(.04,.12))) +
      labs(x=expression('Coefficient '*beta),y=expression(-log[10](P)),
        title=stringr::str_wrap(paste('Adjustment for',voe$factors[[input$voe_factor]]),32),tag='a') +
      voe_theme() + guides(color=guide_legend(order=1),shape=guide_legend(order=2)) +
      theme(legend.box='vertical',legend.spacing.y=grid::unit(0,'pt'),legend.margin=margin(0,0,0,0))
  })
  output$voe_driver_plot <- renderPlot({
    d <- contributions() |> filter(is.finite(change_in_absolute_beta))
    validate(need(nrow(d)>0,'No estimable covariate contributions for this contrast.'))
    d$label <- stringr::str_wrap(unname(voe$factors[d$factor]),20)
    ggplot(d,aes(change_in_absolute_beta,reorder(label,change_in_absolute_beta))) +
      geom_vline(xintercept=0,color='#7D8991',linewidth=.4) +
      geom_col(aes(fill=change_in_absolute_beta>0),width=.62) +
      scale_fill_manual(values=c('FALSE'='#417D95','TRUE'='#B4604C'),guide='none') +
      scale_x_continuous(labels=scales::label_number(),expand=expansion(mult=.12)) +
      labs(x=expression('Change in |'*beta*'|'),y=NULL,title='Covariate contributions',tag='b') +
      voe_theme() + theme(panel.grid.major.y=element_blank(),axis.text.y=element_text(size=10.5))
  })
  output$voe_specification_plot <- renderPlot({
    d <- plot_models()
    factors <- intersect(names(voe$factors),contributions()$factor)
    cells <- do.call(rbind,lapply(factors,function(f) data.frame(
      rank=d$rank,factor=f,included=ifelse(grepl(paste0('\\b',f,'\\b'),d$covariates),
        'Included','Not included'))))
    cells$factor <- factor(cells$factor,levels=rev(factors))
    curve <- ggplot(d,aes(rank,beta,color=included)) +
      geom_hline(yintercept=0,color='#7D8991',linetype=2,linewidth=.4) +
      geom_linerange(aes(ymin=ci_low,ymax=ci_high),alpha=.4,linewidth=.5) +
      geom_point(size=2.2) +
      geom_point(data=d[d$model_id=='primary',],aes(shape='Primary model'),
        fill='white',color=study_colors[['ink']],size=3,stroke=.8) +
      scale_color_manual(values=c('Included'='#417D95','Not included'='#C5A265'),drop=FALSE) +
      scale_shape_manual(values=c('Primary model'=23)) +
      scale_x_continuous(limits=c(.5,nrow(d)+.5),expand=c(0,0)) +
      labs(x=NULL,y=expression('Coefficient '*beta*' (95% CI)'),title='Ordered model estimates',tag='a') +
      voe_theme() + theme(axis.text.x=element_blank(),axis.ticks.x=element_blank(),
        legend.position='top',legend.box='horizontal')
    matrix <- ggplot(cells,aes(rank,factor,fill=included)) +
      geom_tile(width=.9,height=.78) +
      scale_fill_manual(values=c('Included'='#417D95','Not included'='#EDF1F3'),
        breaks=c('Included','Not included')) +
      scale_y_discrete(labels=function(x) stringr::str_wrap(unname(voe$factors[x]),26)) +
      scale_x_continuous(limits=c(.5,nrow(d)+.5),expand=c(0,0),
        breaks=unique(c(1L,round(seq(1,nrow(d),length.out=5)),nrow(d)))) +
      labs(x='Model rank',y=NULL,title='Adjustment specifications',tag='b') +
      voe_theme() + theme(panel.grid=element_blank(),axis.text.y=element_text(size=11),
        axis.ticks.y=element_blank())
    cowplot::plot_grid(curve,matrix,ncol=1,align='v',axis='lr',rel_heights=c(1.1,1))
  })
  output$voe_model_table <- renderReactable({
    m <- models()
    optional <- vapply(m$covariates,function(formula) {
      included <- vapply(names(voe$factors),function(field) grepl(paste0('\\b',field,'\\b'),formula),logical(1))
      if(!any(included)) 'None' else paste(unname(voe$factors[included]),collapse=', ')
    },character(1))
    d <- m |> transmute(Rank=model_rank,Model=ifelse(model_id=='primary','Primary',model_id),
      Status=ifelse(status=='ok','Fitted',gsub('_',' ',status)),N=n,Beta=beta,
      `95% CI lower`=ci_low,`95% CI upper`=ci_high,P=p_value,`−log10(P)`=minus_log10_p,
      `Optional covariates`=optional,Reason=reason)
    reactable(d,searchable=TRUE,defaultPageSize=8,compact=TRUE,defaultSorted=list(Rank='asc'),
      defaultColDef=colDef(minWidth=90,format=colFormat(digits=4)),
      columns=list(Rank=colDef(minWidth=60,format=colFormat(digits=0)),
        N=colDef(format=colFormat(digits=0)),`Optional covariates`=colDef(minWidth=250),
        P=colDef(cell=function(value) if(is.na(value)) '' else format(value,digits=3,scientific=TRUE)),
        Reason=colDef(show=any(!is.na(d$Reason) & nzchar(d$Reason)))))
  })
  output$voe_results_title <- renderText({paste('Robustness of associations with',phenotype_rows()$phenotype[1])})
  output$voe_summary_table <- renderReactable({
    d <- phenotype_rows() |> transmute(Exposure=exposure,Contrast=contrast_label,N=n_voe,
      `β range`=beta_range,`Nominal retention`=nominal_retention,
      `Bonferroni retention`=original_bonferroni_retention,
      `Sign reversal`=ifelse(sign_reversal,'Yes','No'),
      `Significant opposite directions`=ifelse(significant_opposite_signs,'Yes','No'),Models=n_models)
    reactable(d,searchable=TRUE,defaultPageSize=10,defaultSorted=list('β range'='desc'),compact=TRUE,
      defaultColDef=colDef(minWidth=100),columns=list(Exposure=colDef(minWidth=210),
        Contrast=colDef(minWidth=160),`β range`=colDef(format=colFormat(digits=4)),
        `Nominal retention`=colDef(format=colFormat(percent=TRUE,digits=1)),
        `Bonferroni retention`=colDef(format=colFormat(percent=TRUE,digits=1))))
  })
  output$voe_range_plot <- renderPlot({
    ggplot(voe_summary,aes(beta_range,color=group)) + stat_ecdf(linewidth=.8) +
      scale_x_log10(labels=scales::label_number()) +
      scale_y_continuous(labels=scales::label_percent()) + scale_color_manual(values=voe_colors) +
      labs(x=expression('Range of '*beta*' (log scale)'),y='Cumulative proportion',title='Effect variation across the atlas') +
      voe_theme() + guides(color=guide_legend(nrow=2)) +
      theme(legend.position='bottom',legend.text=element_text(size=11))
  })
  metrics <- do.call(rbind,lapply(names(voe_colors),function(g) {
    x <- voe_summary[voe_summary$group==g,]
    data.frame(group=g,metric=c('Nominal significance in every model',
      'Bonferroni significance in at least half','Any sign reversal','Significant opposite directions'),
      n=c(sum(x$nominal_retention==1),sum(x$original_bonferroni_retention>=.5),
        sum(x$sign_reversal),sum(x$significant_opposite_signs)),denominator=nrow(x))
  })) |> mutate(percent=100*n/denominator)
  output$voe_retention_plot <- renderPlot({
    d <- metrics; d$metric <- factor(stringr::str_wrap(d$metric,27),
      levels=rev(unique(stringr::str_wrap(d$metric,27))))
    ggplot(d,aes(percent,metric,color=group,group=group)) +
      geom_point(aes(shape=group),position=position_dodge(width=.55),size=3) +
      geom_text(aes(label=sprintf('%.1f%%',percent)),position=position_dodge(width=.55),
        hjust=-.25,size=4,color='#29343D') +
      scale_color_manual(values=voe_colors) + scale_shape_manual(values=c(16,17)) +
      scale_x_continuous(limits=c(0,115),breaks=c(0,25,50,75,100)) +
      labs(x='Coefficients (%)',y=NULL,title='Robustness across models') +
      voe_theme() + guides(color=guide_legend(nrow=2)) +
      theme(legend.position='bottom',legend.text=element_text(size=11),
        axis.line.y=element_blank(),axis.ticks.y=element_blank())
  })
  output$voe_overview_table <- renderReactable({
    d <- metrics |> transmute(Group=group,Measure=metric,Count=n,Denominator=denominator,Percent=percent)
    reactable(d,pagination=FALSE,defaultColDef=colDef(minWidth=100),
      columns=list(Group=colDef(minWidth=200),Measure=colDef(minWidth=260),Percent=colDef(format=colFormat(digits=1))))
  })
  output$voe_models_download <- downloadHandler(
    filename=function() paste0('VoE_',input$voe_exposure,'_',input$voe_phenotype,'_models.csv'),
    content=function(file) write_summary_csv(models(),file))
  output$voe_drivers_download <- downloadHandler(
    filename=function() paste0('VoE_',input$voe_exposure,'_',input$voe_phenotype,'_contributions.csv'),
    content=function(file) write_summary_csv(contributions(),file))
  output$voe_summary_download <- downloadHandler(
    filename=function() paste0('VoE_',input$voe_phenotype,'_summary.csv'),
    content=function(file) write_summary_csv(phenotype_rows(),file))
}
