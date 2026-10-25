# PE Browser App
# Developed using Posit Shiny
# Chirag Patel
# chirag@hms.harvard
# 12/30/24

library(dplyr)
library(tidyr)
library(forcats)
library(ggplot2)
library(stringr)
library(DT)
library(cowplot)
library(shiny)
library(reactable)
library(igraph)
library(ggridges)


# KNHANES adaptation: retain the upstream Shiny UI and server workflow.
source("R/data.R", local=TRUE)
source("R/style.R", local=TRUE)
source("R/vibration.R", local=TRUE)
source("R/browser.R", local=TRUE)

overview_text <- "This atlas presents associations between 335 exposure indicators and 149 quantitative phenotypes in Korean adults aged 19 years and older, using KNHANES 2007–2024. Browse 24,008 exposure–phenotype pairs and 26,078 coefficient contrasts from survey-weighted analyses."

figure_files <- jsonlite::fromJSON("data/figures.json")

## ui
ui <- navbarPage("KNHANES Atlas", id = "main_nav",
    tabPanel("About",
      mainPanel(width=10,
        h1("The KNHANES Phenome–Exposome Atlas"),
        a(href="research/figures/10_研究流程.png", target="_blank",
          img(`data-atlas-src`="research/figures/10_研究流程.png", class="study-flowchart",
            alt="Figure 1. KNHANES 2007–2024 study workflow: dataset preparation, core atlas and vibration of effects, health applications, measurement extensions and external evaluation.")),
        p(a("View Figure 1 at full resolution",href="research/figures/10_研究流程.png",target="_blank")),
        h2("Overview"), p(overview_text),
        p("The study follows 140,372 participant records through adult eligibility and measurement harmonization to 100,556 contributing adults. It examines association robustness, exposure complementarity, insulin-resistance indices, physiological ageing, subjective memory and external evaluation in NHANES, CHARLS and ELSA."),
        h2("Using the atlas"),
        p("Choose a phenotype, exposure or exposure group from the navigation bar. Search the selector, switch plot tabs, sort and search the summary table, or download the results. Exposure and phenotype catalogs describe the available variables."),
        p("The Vibration of effects module explores the sensitivity of all 24,008 pairs to alternative adjustment sets, covering 26,078 coefficient contrasts and 1,535,744 fitted models. Select an association to inspect model estimates, covariate contributions and robustness."),
        h2("Analysis definitions"),
        p("Models incorporate survey weights, strata and primary sampling units. Coefficients describe standardized outcomes; continuous exposures use the log10 scale, ordinal exposures retain rank scores, and categorical exposures retain their reference comparisons."),
        p("Bonferroni and Benjamini–Yekutieli (BY) correction use the original 26,078 coefficient tests. Pair-level ΔR² is the additional survey-weighted variance explained by the full exposure term. The R² distribution counts each pair once, using its overall-exposure significance family of 24,008 tests."),
        p("Effect-size boxplots summarize absolute standardized coefficients by exposure group. Model comparison displays base-model and fully adjusted coefficients."),
        h2("Data and software"),
        p(a("ZJR analysis software", href="https://github.com/zjy666223/ZJR")),
        p(a("Data and figure downloads", href="#", onclick="$('a[data-value=\"Downloads\"]').tab('show');return false;"))
      )
    ),
    tabPanel("Browse By Phenotype",
        sidebarPanel(
            selectInput("pvarname", h3("By Phenotype"), choices=setNames(p_variables$pvarname,p_variables$pvardesc_selector), selected="p_bmi"),
            actionButton("copy_pheno_link", "Copy Link to This Phenotype", icon = icon("link"))
        ),
        mainPanel(
            h1(textOutput("pvariable_description")),
            h2("Category:", textOutput("pvariable_subcategory")),
            tabsetPanel(type = "tabs",
                tabPanel("-log(P) vs. Exposure Group", plotOutput("by_phenotype_manhattan_plot", height="520px")),
                tabPanel("Effect Sizes", plotOutput("by_phenotype_effect_size",height = "600px"), p("Absolute standardized coefficients by exposure group; categorical contrasts retain their original reference levels.")),
                tabPanel("R^2", plotOutput("by_phenotype_r2_plot")),
                tabPanel("-log(P) vs. Effect Size", plotOutput("by_phenotype_volcano_plot"),
                         p("Points in the background depict summary stats for the entire category")),
                tabPanel("Globe", plotOutput("by_phenotype_globe_plot"),
                        p("Nodes are exposure measurements associated with the phenotype. Edges show partial correlations with |r| > 0.25 and Bonferroni P < 0.05; up to 100 strongest edges are displayed."),
                        h3("Globe Abbreviation Legend"),
                         DTOutput("by_phenotype_globe_legend_table")),
                tabPanel("Model comparison", plotOutput("by_phenotype_estimate_plot"))
            ),
            h3("Summary Statistics"),
            reactableOutput("by_phenotype_table"),
            ## download button
            downloadButton("by_phenotype_table_download", "Download Summary Statistics"),
            ## put in correlations here
            h3("Similar Phenotypes"), p("Association-profile Pearson correlation; coefficients with nominal P ≥ 0.10 set to zero, with at least 20 shared coefficients."),
            ## put in multivariate model
            reactableOutput("exposure_corr_table")
        )
    ),

    tabPanel("Browse By Exposure",
             sidebarPanel(
                 selectInput("evarname", h3("By Exposure"), choices=setNames(e_variables$evarname,e_variables$evardesc_selector), selected="e_blood_mercury"),
                 actionButton("copy_expo_link", "Copy Link to This Exposure", icon = icon("link"))
             ),
             mainPanel(
               h1(textOutput("evariable_description")),
               h2("Category:", textOutput("evariable_subcategory")),
               tabsetPanel(type = "tabs",
                           tabPanel("-log(P) vs. Effect Size", plotOutput("by_exposure_volcano_plot"),p("Points in the background depict summary stats for the entire category")),
                           tabPanel("ES Histogram", plotOutput("by_exposure_context_plot"), p("Coefficients with BY q < 0.05")),
                           tabPanel("R^2", plotOutput("by_exposure_r2_plot")),
                           tabPanel("Model comparison", plotOutput("by_exposure_estimate_plot"))
               ),
               h3("Summary Statistics"),
               reactableOutput("by_exposure_table"),
               ## download button
               downloadButton("by_exposure_table_download", "Download Summary Statistics"),
               ## put in correlations here
               h3("Similar Exposures"), p("Association-profile similarity. Profiles are defined for each exposure contrast."),
               ## put in multivariate model
               reactableOutput("phenotype_corr_table")
             )
    ),

    tabPanel("Browse by Exposure Group",
               sidebarPanel(
               selectInput("egroup", h3("By Group"), choices=setNames(e_category_strs$cat_subcat,e_category_strs$cat_subcat), selected="Environmental chemicals"),
               actionButton("copy_group_link", "Copy Link to This Group", icon = icon("link"))
             ),
             mainPanel(
               h1(textOutput("egroup_description")),
               tabsetPanel(type="tabs",
                           tabPanel("-log(P) vs. Effect Size", plotOutput("by_exposure_group_volcano_plot")),
                           tabPanel("ES Histogram", plotOutput("by_exposure_group_context_plot")),
                           tabPanel("R^2", plotOutput("by_exposure_group_r2_plot")),
                           tabPanel("Model comparison", plotOutput("by_exposure_group_estimate_plot"))
                ),
               h3("Summary Statistics for each E"),
               reactableOutput("by_exposure_group_table"),
               downloadButton("by_exposure_group_table_download", "Download Summary Statistics")
             )
    ),
  tabPanel("E Catalog",
    mainPanel(
      h1("Exposome Catalog"),
      reactableOutput("e_catalog_table")
    )
  ),
  tabPanel("P Catalog",
           mainPanel(
             h1("Phenome Catalog"),
             reactableOutput("p_catalog_table")
           )
  )
,
  vibration_ui(),
  tabPanel("Downloads", mainPanel(
    h1("Results and figure downloads"),
    h3("Summary results"),
    tags$ul(lapply(c("associations", "exposures", "phenotypes", "joint", "network", "exposure_profiles", "phenotype_profiles", "vibration"), function(x)
      tags$li(a(gsub("_", " ", x), href=paste0("research/data/",x,".csv"), download=NA)))),
    h3("Study figures"),
    selectInput("figure", "Select a figure", choices=setNames(seq_len(nrow(figure_files)),figure_files$title)),
    uiOutput("figure_preview"),
    h3("Joint exposure models"), reactableOutput("joint_table")
  ))

)

ui <- tagList(tags$head(includeCSS("www/study.css")), includeScript("www/browser.js"), ui)

### table and figure functions

## for exposure or phenotypes
plot_adjusted_r2_cdf <- function(to_plot) {
  p <- ggplot(to_plot, aes(r2_adjusted_vs_base, color=sig_levels))
  p <- p + stat_ecdf() + scale_x_continuous(labels=scales::label_percent()) + study_sig_color()
  p <- p + study_theme() + xlab("Additional variance explained (ΔR²)") + ylab("Cumulative proportion of pairs")
  p <- p + theme(legend.position = "bottom")
  p
}


plot_volcano <- function(to_plot, bg=NULL) {
  p <- ggplot(to_plot, aes(estimate, -log10(p.value), color=sig_levels))
  p <- p + geom_point(shape = 1, size = 1) # color = "black")
  if(!is.null(bg)) {
    p <- p + geom_point(data=bg, aes(estimate, -log10(p.value)), alpha=.01)
  }
  p <- p + scale_x_continuous() + study_sig_color()
  p <- p + study_theme() + xlab("Standardized coefficient β (original contrast)") + ylab("−log10 coefficient P (capped at 20)")
  p
}

plot_estimates <- function(to_plot) {
  validate(need(nrow(to_plot)>0, "No model comparison available for this selection."))
  p <- ggplot(to_plot, aes(x=estimate_unadjusted, y=estimate))
  p <- p + geom_point(shape = 1, size = 1.7, color = study_colors[["blue"]]) + scale_x_continuous() + scale_y_continuous()
  p <- p + geom_abline(linetype="dashed")
  p <- p + xlab("Base-model coefficient β") + ylab("Fully adjusted coefficient β")
  p <- p + study_theme()
  p
}


reactable_tibble <- function(meta_obj) {
  meta_obj |> transmute(p_description=pvardesc, e_description=evardesc, comparison,
    effect.size=estimate, ci_low, ci_high, r.squared=rsq_adjusted_base_diff,
    p.value=p, BY=q, Bonferroni=bonferroni_p, sig_levels,
    total_sample_size=total_n, n_surveys=nobs, I2=i.squared.uwls,
    exposure_id=evarname, phenotype_id=pvarname, pair_id, contrast, years)
}

reactable_summary_stats <- function(meta_obj) {
  display <- reactable_tibble(meta_obj)
  reactable(display, defaultSorted=list(r.squared="desc"), searchable=TRUE,
    defaultPageSize=10, showPageSizeOptions=TRUE, pageSizeOptions=c(10,25,50),
    striped=FALSE, highlight=FALSE, bordered=FALSE, compact=TRUE,
    defaultColDef=colDef(minWidth=85), columns=list(
      p_description=colDef(name="Phenotype",minWidth=145),
      e_description=colDef(name="Exposure",minWidth=170),
      comparison=colDef(name="Contrast",minWidth=125),
      effect.size=colDef(name="β",format=colFormat(digits=3)),
      ci_low=colDef(name="95% CI low",format=colFormat(digits=3)),
      ci_high=colDef(name="95% CI high",format=colFormat(digits=3)),
      r.squared=colDef(name="ΔR²",format=colFormat(digits=4)),
      p.value=colDef(name="P",cell=function(v) format(v,digits=3,scientific=TRUE)),
      BY=colDef(name="BY q",cell=function(v) format(v,digits=3,scientific=TRUE)),
      Bonferroni=colDef(show=FALSE),sig_levels=colDef(name="Significance",minWidth=110),
      total_sample_size=colDef(name="N",format=colFormat(separators=TRUE)),
      n_surveys=colDef(name="Years"),I2=colDef(name="I² (%)",format=colFormat(digits=1)),
      exposure_id=colDef(show=FALSE),phenotype_id=colDef(show=FALSE),
      pair_id=colDef(show=FALSE),contrast=colDef(show=FALSE),years=colDef(show=FALSE)))
}



plot_manhattan <- function(to_plot) {
  PCAP <- 20
  ## order in terms of number found; or R2.
  enewsubcategory_order <- to_plot |> filter(sig_levels == 'Bonf.<0.05') |> group_by(enewsubcategory) |> summarize(med_r2=mean(rsq_adjusted_base_diff)) |> arrange(-med_r2) |> mutate(group_number = row_number())

  to_plot <- to_plot |> left_join(enewsubcategory_order |> select(enewsubcategory, group_number))
  eplot_order <- to_plot |> select(evarname ,enewsubcategory, group_number) |> unique() |> arrange(group_number) |> mutate(order_number = row_number())

  xaxis_labels <- eplot_order |> group_by(group_number,enewsubcategory) |> summarize(med_x=round(median(order_number)), min_x=min(order_number), max_x=max(order_number))
  to_plot <- to_plot |> left_join(eplot_order |> select(evarname,order_number))
  p <- ggplot(to_plot |> arrange(order_number), aes(order_number, -log10(p.value)))
  p <- p + geom_point(aes(color=sig_levels), shape=20) + study_sig_color()
  p <- p + scale_y_continuous(limits=c(0, PCAP+1))
  p <- p + scale_x_continuous(breaks = xaxis_labels$med_x,  labels = stringr::str_wrap(xaxis_labels$enewsubcategory, 20))
  p <- p + geom_vline(data=xaxis_labels, aes(xintercept=max_x), linetype='dotted', col = 'black') + study_theme()
  #p <- p + theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1), legend.position = "bottom")
  p <- p + theme(axis.text.x = element_blank(), legend.position = "bottom")
  p1 <- p + xlab("") + ylab("−log10 P (capped at 20)")

  p <- ggplot(to_plot |> arrange(order_number), aes(order_number, rsq_adjusted_base_diff))
  p <- p + geom_point(aes(color=sig_levels), shape=20) + study_sig_color()
  p <- p + scale_x_continuous(breaks = xaxis_labels$med_x,  labels = stringr::str_wrap(xaxis_labels$enewsubcategory, 20))
  p <- p + geom_vline(data=xaxis_labels, aes(xintercept=max_x), linetype='dotted', col = 'black') + study_theme()
  p <- p + theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1), legend.position = "bottom")
  p2 <- p + xlab("") + ylab("ΔR²")
  legend <- cowplot::get_legend(p1 + theme(legend.position="top"))
  panels <- cowplot::plot_grid(p1 + theme(legend.position="none"),
    p2 + theme(legend.position="none"), nrow=2, rel_heights=c(1,1.4))
  combined <- gridExtra::arrangeGrob(legend, panels, ncol=1,
    heights=grid::unit.c(sum(legend$height), grid::unit(1,"npc")-sum(legend$height)))
  cowplot::ggdraw() + cowplot::draw_grob(grid::grobTree(combined))
}

plot_effect_size <- function(to_plot) {
  # distribution
  pvarname_lcl <- unique(to_plot$pvarname)[1]
  p <- ggplot(to_plot |> filter(!is.na(sig_levels)) |> mutate(sig_levels = factor(sig_levels, levels=c("> BY & Bonf.", "BY<0.05", "Bonf.<0.05"))),
              aes(y=exposure_level, x=I(abs(estimate)), fill=sig_levels))
  p <- p + geom_violin(orientation = "y", scale = "width", width = 0.5)
  #p <- p + geom_histogram(orientation = "y", width = 0.5)
  p <- p + xlab("Absolute Value Effect Size [1 Unit of Phenotype (original units)]") + ylab("Quantile of Exposure") + ylab("Percentile of Exposure")
  p <- p + study_sig_fill()
  p <- p + study_theme() + coord_flip() + theme(legend.position = "bottom")
  p
}
plot_effect_size_box <- function(to_plot) {

  to_plot <- to_plot |>
    filter(!is.na(sig_levels)) |>
    mutate(
      sig_levels = factor(sig_levels, levels = c("> BY & Bonf.", "BY<0.05", "Bonf.<0.05")),
      exposure_level = factor(exposure_level)
    )


  p <- ggplot(to_plot, aes(x = exposure_level, y = abs(estimate), fill = sig_levels)) +
    # notch = TRUE can help show if medians differ significantly
    geom_boxplot(outlier.size = 1, alpha = 0.8) +

    # Flip the coordinates to make it horizontal
    coord_flip() +

    xlab("Exposure group") +
    ylab("Absolute standardized coefficient |β|") +
    study_sig_fill() +
    study_theme() +
    theme(legend.position = "bottom")

  return(p)
}

globe_data <- function(exposure_tibble) {
  ids <- unique(exposure_tibble$evarname)
  edges <- ee |> filter(variable_x %in% ids, variable_y %in% ids,
    abs(estimate)>.25, p_bonferroni<.05) |> arrange(desc(abs(estimate))) |> head(100)
  nodes <- network_nodes |> filter(node_id %in% c(edges$xvarname, edges$yvarname)) |>
    mutate(abbr=sprintf("E%02d",row_number()),
      category=unname(domain_names[category]))
  list(edges=edges,nodes=nodes)
}

exposome_globe_plot <- function(exposure_tibble) {
  d <- globe_data(exposure_tibble)
  validate(need(nrow(d$edges)>0,"No partial correlations meet the selected thresholds."))
  g <- graph_from_data_frame(d$edges |> select(xvarname,yvarname,estimate), directed=FALSE,
    vertices=d$nodes |> select(node_id,everything()))
  E(g)$color <- ifelse(E(g)$estimate>0,study_colors[["red"]],study_colors[["blue"]])
  coords <- layout_in_circle(g)
  par(mar=c(0,0,0,0))
  plot(g, layout=coords, vertex.size=10, vertex.color=MASTER_COLORS[V(g)$category],
    vertex.label=V(g)$abbr, vertex.label.cex=.7, vertex.label.color=study_colors[["ink"]],
    vertex.label.family="sans", edge.curved=FALSE,
    edge.width=sqrt(abs(E(g)$estimate))*4)
  legend("bottomleft",legend=c("Positive","Negative"),
    col=study_colors[c("red","blue")],lty=1,lwd=2,bty="n",cex=.85)
}


write_summary_csv <- function(x, file) {
  formatted <- x |> mutate(across(where(is.double),
    ~ifelse(is.na(.x), NA_character_, sprintf("%.17g", .x))))
  readr::write_csv(formatted, file, na="")
}

# server logic
server <- function(input, output, session) {
    vibration_server(input, output, session)
    # Parse URL query parameters to set dropdowns and navigate to the right tab
    observe({
      query <- parseQueryString(input$atlas_url_search)
      if (!is.null(query$phenotype) && query$phenotype %in% p_variables$pvarname) {
        updateSelectInput(session, "pvarname", selected = query$phenotype)
        updateNavbarPage(session, "main_nav", selected = "Browse By Phenotype")
      }
      if (!is.null(query$exposure) && query$exposure %in% e_variables$evarname) {
        updateSelectInput(session, "evarname", selected = query$exposure)
        updateNavbarPage(session, "main_nav", selected = "Browse By Exposure")
      }
      if (!is.null(query$group) && query$group %in% e_category_strs$cat_subcat) {
        updateSelectInput(session, "egroup", selected = query$group)
        updateNavbarPage(session, "main_nav", selected = "Browse by Exposure Group")
      }
    }) |> bindEvent(input$atlas_url_search, once = TRUE)

    # Copy link buttons - show modal with selectable link
    observeEvent(input$copy_pheno_link, {
      base_url <- input$atlas_site_url
      link <- paste0(base_url, "?phenotype=", input$pvarname)
      showModal(modalDialog(
        title = "Shareable Link",
        tags$input(type = "text", value = link, id = "share_link_text",
                   style = "width:100%; padding:8px; font-size:14px;", readonly = "readonly"),
        tags$script(HTML("document.getElementById('share_link_text').select();")),
        footer = modalButton("Close"),
        easyClose = TRUE
      ))
    })

    observeEvent(input$copy_expo_link, {
      base_url <- input$atlas_site_url
      link <- paste0(base_url, "?exposure=", input$evarname)
      showModal(modalDialog(
        title = "Shareable Link",
        tags$input(type = "text", value = link, id = "share_link_text",
                   style = "width:100%; padding:8px; font-size:14px;", readonly = "readonly"),
        tags$script(HTML("document.getElementById('share_link_text').select();")),
        footer = modalButton("Close"),
        easyClose = TRUE
      ))
    })

    observeEvent(input$copy_group_link, {
      base_url <- input$atlas_site_url
      link <- paste0(base_url, "?group=", URLencode(input$egroup, reserved = TRUE))
      showModal(modalDialog(
        title = "Shareable Link",
        tags$input(type = "text", value = link, id = "share_link_text",
                   style = "width:100%; padding:8px; font-size:14px;", readonly = "readonly"),
        tags$script(HTML("document.getElementById('share_link_text').select();")),
        footer = modalButton("Close"),
        easyClose = TRUE
      ))
    })

    output$by_phenotype_volcano_plot <- renderPlot({
        pvarn <- input$pvarname
        pcat <- p_variables |> filter(pvarname == pvarn) |> pull(pcategory)

        #to_plot <- tbl(pool, "adjusted_meta_2") |> filter(pvarname == pvarn) |> select(estimate, p.value, sig_levels) |> collect()
        to_plot <-adjusted_meta_2 |> filter(pvarname == pvarn) |> select(estimate, p.value, sig_levels)
        to_plot <- to_plot |> mutate(p.value = ifelse(p.value < 1e-20, 1e-20, p.value))
        #bg <- tbl(pool, "adjusted_meta_2") |> filter(pcategory == pcat) |> select(estimate, p.value, sig_levels) |> collect()
        bg <- adjusted_meta_2 |> filter(pcategory == pcat) |> select(estimate, p.value, sig_levels) #|> collect()
        bg <- bg |> mutate(p.value = ifelse(p.value < 1e-20, 1e-20, p.value))
        plot_volcano(to_plot, bg)
    })

    output$by_phenotype_manhattan_plot <- renderPlot({
      pvarn <-input$pvarname
      pcat <- p_variables |> filter(pvarname == pvarn) |> pull(pcategory)
      #to_plot <- tbl(pool, "adjusted_meta_2") |> filter(pvarname == pvarn) |> collect()
      to_plot <- adjusted_meta_2 |> filter(pvarname == pvarn)
      to_plot <- to_plot |> mutate(p.value = ifelse(p.value < 1e-20, 1e-20, p.value))
      plot_manhattan(to_plot)
    })


    output$by_phenotype_globe_plot <- renderPlot({
      pvarn <-input$pvarname
      #exposures_to_plot <- tbl(pool, "adjusted_meta_2") |> filter(pvarname == pvarn, sig_levels == "Bonf.<0.05")|> select(evarname)
      exposures_to_plot <- adjusted_meta_2 |> filter(pvarname == pvarn, sig_levels == "Bonf.<0.05")|> select(evarname)
      validate(need(nrow(exposures_to_plot) > 0, "No exposures pass the Bonferroni significance threshold for this phenotype."))
      exposome_globe_plot(exposure_tibble = exposures_to_plot)
    })
    output$by_phenotype_globe_legend_table <- renderDT({
      selected <- adjusted_meta_2 |> filter(pvarname==input$pvarname,sig_levels=="Bonf.<0.05") |> select(evarname)
      legend <- globe_data(selected)$nodes |> select(Abbreviation=abbr,Exposure=label,Category=category)
      datatable(legend, rownames=FALSE, class="compact", options=list(pageLength=10))
    })
    output$by_phenotype_effect_size <-renderPlot({
      pvarn <-input$pvarname
      pcat <- p_variables |> filter(pvarname == pvarn) |> pull(pcategory)
      #es <- tbl(pool, "pe_quantile_ns") |> filter(pvarname == pvarn) |> collect()
      es <- pe_quantile_ns |> filter(pvarname == pvarn) #|> collect()
      plot_effect_size_box(es)
    })

    output$by_phenotype_r2_plot <- renderPlot({
        pvarn <- input$pvarname
        #to_plot <- tbl(pool, "adjusted_meta_2") |> filter(pvarname==pvarn) |> distinct(pair_id,.keep_all=TRUE) |> transmute(rsq_adjusted_base_diff,rsq_adjusted_diff=NA_real_,sig_levels=pair_sig_levels) |> collect()
        to_plot <- adjusted_meta_2 |> filter(pvarname==pvarn) |> distinct(pair_id,.keep_all=TRUE) |> transmute(rsq_adjusted_base_diff,rsq_adjusted_diff=NA_real_,sig_levels=pair_sig_levels) #|> collect()
        to_plot <- to_plot |> rename(r2_adjusted_vs_base=rsq_adjusted_base_diff, r2_adjusted_vs_unadjusted=rsq_adjusted_diff)
        plot_adjusted_r2_cdf(to_plot)
    })

    output$by_phenotype_estimate_plot <- renderPlot({
        pvarn <- input$pvarname
        #to_plot <- tbl(pool, "expos_wide") |> filter(pvarname == pvarn) |> select(estimate_2,estimate_1) |> rename(estimate=estimate_2, estimate_unadjusted=estimate_1) |> collect()
        to_plot <- expos_wide |> filter(pvarname == pvarn) |> select(estimate_2,estimate_1) |> rename(estimate=estimate_2, estimate_unadjusted=estimate_1) #|> collect()
        plot_estimates(to_plot)
    })

    output$by_phenotype_table <- renderReactable({
      reactable_summary_stats(adjusted_meta_2 |> filter(pvarname == input$pvarname))
    })

    output$by_phenotype_table_download <- downloadHandler(
      ## to implement
      filename = function() {
        pvarn <- input$pvarname
        paste("by_pheno-", pvarn, '-', Sys.Date(), ".csv", sep="")
      },
      content = function(file) {
        pvarn <- input$pvarname
        #to_react <- tbl(pool, "adjusted_meta_2") |> filter(pvarname == pvarn) |> reactable_tibble()
        to_react <-  adjusted_meta_2 |> filter(pvarname == pvarn) |> reactable_tibble()
        write_summary_csv(x=to_react, file)
      }
    )

    output$pvariable_description <- renderText({
        pvarn <- input$pvarname
        #ret <- tbl(pool, "p_variable_domain") |> filter(Variable.Name == pvarn) |> pull(pvardesc)
        ret <- p_variable_domain |> filter(Variable.Name == pvarn) |> pull(pvardesc)
        ret[1]
    })

    output$pvariable_category <- renderText({
      pvarn <- input$pvarname
      #ret <- tbl(pool, "p_variable_domain") |> filter(Variable.Name == pvarn) |> pull(pcategory)
      ret <- p_variable_domain |> filter(Variable.Name == pvarn) |> pull(pcategory)
      ret[1]
    })

    output$evariable_description <- renderText({
        evarn <- input$evarname
        #ret <- tbl(pool, "e_variable_domain") |> filter(Variable.Name == evarn) |> pull(evardesc)
        ret <- e_variable_domain |> filter(Variable.Name == evarn) |> pull(evardesc)
        ret[1]
    })

    output$evariable_category <- renderText({
      evarn <- input$evarname
      #ret <- tbl(pool, "e_variable_domain") |> filter(Variable.Name == evarn) |> pull(ecategory)
      ret <- e_variable_domain |> filter(Variable.Name == evarn) |> pull(ecategory)
      ret[1]
    })

    output$pvariable_subcategory <- renderText({
      pvarn <- input$pvarname
      ret <- p_variables |> filter(pvarname == pvarn) |> pull(cat_subcat)
      ret[1]
    })

    output$evariable_subcategory <- renderText({
      evarn <- input$evarname
      ret <- e_variables |> filter(evarname == evarn) |> pull(cat_subcat)
      ret[1]
    })

    output$by_exposure_volcano_plot <- renderPlot({
        evarn <- input$evarname
        ecat <- e_variables |> filter(evarname == evarn) |> pull(ecategory)
        #to_plot <- tbl(pool, "adjusted_meta_2") |> filter(evarname == evarn) |> select(estimate, p.value, sig_levels) |> collect()
        to_plot <- adjusted_meta_2 |> filter(evarname == evarn) |> select(estimate, p.value, sig_levels) #|> collect()
        to_plot <- to_plot |> mutate(p.value = ifelse(p.value < 1e-20, 1e-20, p.value))
        #bg <- tbl(pool, "adjusted_meta_2") |> filter(ecategory == ecat) |> select(estimate, p.value, sig_levels) |> collect()
        bg <- adjusted_meta_2 |> filter(ecategory == ecat) |> select(estimate, p.value, sig_levels) #|> collect()
        bg <- bg |> mutate(p.value = ifelse(p.value < 1e-20, 1e-20, p.value))
        plot_volcano(to_plot, bg)
    })

    output$by_exposure_r2_plot <- renderPlot({
      evarn <- input$evarname
      #to_plot <- tbl(pool, "adjusted_meta_2") |> filter(evarname==evarn) |> distinct(pair_id,.keep_all=TRUE) |> transmute(rsq_adjusted_base_diff,rsq_adjusted_diff=NA_real_,sig_levels=pair_sig_levels) |> collect()
      to_plot <- adjusted_meta_2 |> filter(evarname==evarn) |> distinct(pair_id,.keep_all=TRUE) |> transmute(rsq_adjusted_base_diff,rsq_adjusted_diff=NA_real_,sig_levels=pair_sig_levels) #|> collect()
      to_plot <- to_plot |> rename(r2_adjusted_vs_base=rsq_adjusted_base_diff, r2_adjusted_vs_unadjusted=rsq_adjusted_diff)
      plot_adjusted_r2_cdf(to_plot)
    })


    output$by_exposure_table <- renderReactable({
      reactable_summary_stats(adjusted_meta_2 |> filter(evarname == input$evarname))
    })


    output$by_exposure_table_download <- downloadHandler(
      ## to implement
      filename = function() {
        evarn <- input$evarname
        paste("by_expo-", evarn, '-', Sys.Date(), ".csv", sep="")
      },
      content = function(file) {
        evarn <- input$evarname
        #to_react <- tbl(pool, "adjusted_meta_2") |> filter(evarname == evarn) |> reactable_tibble()
        to_react <- adjusted_meta_2 |> filter(evarname == evarn) |> reactable_tibble()
        write_summary_csv(x=to_react, file)
      }
    )

    output$by_exposure_estimate_plot <- renderPlot({
      evarn <- input$evarname
      #to_plot <- tbl(pool, "expos_wide") |> filter(evarname == evarn) |> select(estimate_2,estimate_1) |> rename(estimate=estimate_2, estimate_unadjusted=estimate_1) |> collect()
      to_plot <- expos_wide |> filter(evarname == evarn) |> select(estimate_2,estimate_1) |> rename(estimate=estimate_2, estimate_unadjusted=estimate_1) #|> collect()
      plot_estimates(to_plot)
    })

    output$by_exposure_context_plot <- renderPlot({
      evarn <- input$evarname
      #m <- tbl(pool, "adjusted_meta_2") |> filter(pval_BY < 0.05) |> filter(ecategory != 'allergy')
      m <- adjusted_meta_2 |> filter(pval_BY < 0.05) |> filter(ecategory != 'allergy')
      validate(need(any(m$evarname == evarn), "No coefficients with BY q < 0.05 for this exposure."))
      e_estimate <- m |> filter(evarname == evarn) |> select(estimate,sig_levels) #|> collect()
      vardesc <- e_variables |> filter(evarname == evarn)  |> pull(evardesc)
      vardesc <- vardesc[1]
      other_estimates <- m |> filter(evarname != evarn) |> select(ecategory, esubcategory,estimate, sig_levels) |> collect()
      other_estimates <- other_estimates |> mutate(cat_subcat=ifelse(!is.na(esubcategory), paste(ecategory, esubcategory, sep="-"), ecategory ))
      other_estimates <- other_estimates |> select(-c(ecategory, esubcategory))
      to_plot <- e_estimate |> mutate(cat_subcat=vardesc) |> rbind(other_estimates)
      to_plot <- to_plot |> mutate(col=ifelse(cat_subcat == vardesc, 'red', 'black'))
      to_plot <- to_plot |> mutate(cat_subcat=fct_relevel(cat_subcat, vardesc, after = 0 ))
      p <- ggplot(to_plot, aes(y=cat_subcat, x=estimate, fill=col))
      p <- p + geom_density_ridges(scale = 2.1, alpha=.85, color="#78909A", linewidth=.3) + scale_x_continuous()
      p <- p + study_theme() + ylab("") + xlab("Standardized coefficient β") + study_context_fill()
      p <- p + theme(legend.position = "none")
      p
    })

    output$exposure_corr_table <- renderReactable({
      to_react <- exposure_correlation |> filter(x==input$pvarname) |>
        left_join(p_variables,by=c("y"="pvarname")) |>
        select(Phenotype=pvardesc,Category=pcategory,Correlation=r,Shared=n_shared)
      reactable(to_react |> arrange(desc(Correlation)), searchable=TRUE,
        columns=list(Correlation=colDef(format=colFormat(digits=3))))
    })

    output$phenotype_corr_table <- renderReactable({
      own <- profile_rows |> filter(exposure_id==input$evarname)
      to_react <- phenotype_correlation |> filter(x %in% own$profile_id) |>
        left_join(profile_rows |> select(y=profile_id,Exposure=label),by="y") |>
        left_join(own |> select(x=profile_id,Selected=label),by="x") |>
        select(Exposure,Selected,Correlation=r,Shared=n_shared) |> arrange(desc(Correlation))
      reactable(to_react,searchable=TRUE,columns=list(Correlation=colDef(format=colFormat(digits=3))))
    })

    output$egroup_description <- renderText({
      input$egroup
    })

    output$by_exposure_group_volcano_plot <- renderPlot({
      cat_sub <- input$egroup
      category_and_sub <- e_category_strs |> filter(cat_subcat == cat_sub)
      subcategory_str <- category_and_sub |> pull(esubcategory)
      ecategory_str <- category_and_sub |> pull(ecategory)
      #to_plot <- tbl(pool, "adjusted_meta_2") |> filter(ecategory == ecategory_str)
      to_plot <- adjusted_meta_2 |> filter(ecategory == ecategory_str)
      if(!is.na(subcategory_str)) {
        to_plot <- to_plot |> filter(esubcategory == subcategory_str)
      }
      to_plot <- to_plot |> select(estimate, p.value, sig_levels) #|> collect()
      to_plot <- to_plot |> mutate(p.value = ifelse(p.value < 1e-20, 1e-20, p.value))
      plot_volcano(to_plot)
    })


    output$by_exposure_group_table <- renderReactable({
      reactable_summary_stats(adjusted_meta_2 |> filter(ecategory == input$egroup))
    })

    output$by_exposure_group_table_download <- downloadHandler(
      filename = function() {
        cat_sub <- input$egroup
        paste("by_expo_group-", cat_sub, '-', Sys.Date(), ".csv", sep="")
      },
      content = function(file) {
        cat_sub <- input$egroup
        category_and_sub <- e_category_strs |> filter(cat_subcat == cat_sub)
        subcategory_str <- category_and_sub |> pull(esubcategory)
        ecategory_str <- category_and_sub |> pull(ecategory)
        #to_react <- tbl(pool, "adjusted_meta_2") |> filter(ecategory == ecategory_str)
        to_react <- adjusted_meta_2 |> filter(ecategory == ecategory_str)
        if(!is.na(subcategory_str)) {
          to_react <- to_react |> filter(esubcategory == subcategory_str)
        }

        write_summary_csv(x=to_react |> reactable_tibble(), file)
      }
    )

    output$by_exposure_group_r2_plot <- renderPlot({
      cat_sub <- input$egroup
      category_and_sub <- e_category_strs |> filter(cat_subcat == cat_sub)
      subcategory_str <- category_and_sub |> pull(esubcategory)
      ecategory_str <- category_and_sub |> pull(ecategory)
      #to_plot <- tbl(pool, "adjusted_meta_2") |> filter(ecategory == ecategory_str)
      to_plot <- adjusted_meta_2 |> filter(ecategory == ecategory_str)
      if(!is.na(subcategory_str)) {
        to_plot <- to_plot |> filter(esubcategory == subcategory_str)
      }
      to_plot <- to_plot |> distinct(pair_id,.keep_all=TRUE) |> transmute(rsq_adjusted_base_diff,rsq_adjusted_diff=NA_real_,sig_levels=pair_sig_levels)
      to_plot <- to_plot |> rename(r2_adjusted_vs_base=rsq_adjusted_base_diff, r2_adjusted_vs_unadjusted=rsq_adjusted_diff)
      plot_adjusted_r2_cdf(to_plot)
    })

    output$by_exposure_group_estimate_plot <- renderPlot({
      cat_sub <- input$egroup
      category_and_sub <- e_category_strs |> filter(cat_subcat == cat_sub)
      subcategory_str <- category_and_sub |> pull(esubcategory)
      ecategory_str <- category_and_sub |> pull(ecategory)
      #to_plot <- tbl(pool, "expos_wide") |> filter(ecategory == ecategory_str)
      to_plot <- expos_wide |> filter(ecategory == ecategory_str)
      if(!is.na(subcategory_str)) {
        to_plot <- to_plot |> filter(esubcategory == subcategory_str)
      }
      to_plot <- to_plot |> select(estimate_2,estimate_1) |> rename(estimate_unadjusted=estimate_1, estimate=estimate_2) |> collect()
      plot_estimates(to_plot)
    })

    output$by_exposure_group_context_plot <- renderPlot({
      cat_sub <- input$egroup
      #to_plot <- tbl(pool, "adjusted_meta_2") |> filter(pval_BY < 0.05) |> collect() |>
      #  mutate(cat_subcat=ifelse(!is.na(esubcategory), paste(ecategory, esubcategory, sep="-"), ecategory ))

      to_plot <- adjusted_meta_2 |> filter(pval_BY < 0.05)  |>
        mutate(cat_subcat=ifelse(!is.na(esubcategory), paste(ecategory, esubcategory, sep="-"), ecategory ))


      to_plot <- to_plot |> mutate(col=ifelse(cat_subcat == cat_sub, 'red', 'black'))
      to_plot <- to_plot |> mutate(cat_subcat=fct_relevel(cat_subcat, cat_sub, after = 0 ))
      p <- ggplot(to_plot, aes(y=cat_subcat, x=estimate, fill=col))
      p <- p + geom_density_ridges(scale = 2.1, alpha=.85, color="#78909A", linewidth=.3) + scale_x_continuous()
      p <- p + study_theme() + ylab("") + xlab("Standardized coefficient β") + study_context_fill()
      p <- p + theme(legend.position = "none")
      p

    })

  output$e_catalog_table <- renderReactable({
    #am2 <- tbl(pool, "adjusted_meta_2") |> select(evarname, enewsubcategory, evardesc) |> collect() |> unique()
    am2 <- adjusted_meta_2 |> select(evarname, enewsubcategory, evardesc) |> unique()
    reactable(am2 |> rename(ID=evarname, Category=enewsubcategory, Description=evardesc), filterable = TRUE, searchable = TRUE, pageSizeOptions = c(50, 100, 200), showPageSizeOptions = TRUE)
  })

  output$p_catalog_table <- renderReactable({
    #am2 <- tbl(pool, "adjusted_meta_2") |> select(pvarname, pnewsubcategory, pvardesc) |> collect() |> unique()
    am2 <- adjusted_meta_2 |> select(pvarname, pnewsubcategory, pvardesc) |> unique()
    reactable(am2 |> rename(ID=pvarname, Category=pnewsubcategory, Description=pvardesc), filterable = TRUE, searchable = TRUE, pageSizeOptions = c(50, 100, 200), showPageSizeOptions = TRUE)
  })

  output$figure_preview <- renderUI({
    req(input$figure)
    f <- figure_files[as.integer(input$figure),]
    label <- if (grepl("\\.pdf$",f$file,ignore.case=TRUE)) "Download PDF" else "Download PNG"
    tagList(p(a(label,href=paste0("research/",f$file),download=f$source_file)),
      img(`data-atlas-src`=paste0("research/",f$preview),alt=f$title,style="max-width:100%;height:auto;"))
  })
  output$joint_table <- renderReactable({
    x <- readr::read_csv("data/joint.csv",show_col_types=FALSE)
    reactable(x,searchable=TRUE,defaultSorted=list(delta_r2="desc"),
      defaultColDef=colDef(format=colFormat(digits=4)))
  })

}

shinyApp(ui, server)



