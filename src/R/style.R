# Study-wide colors are named so filtering cannot change their meaning.
study_colors <- c(blue='#417D95', red='#B4604C', gold='#C5A265',
  grey='#A5AFB8', pale='#D9E5E9', ink='#27343C')
sig_colors <- c('> BY & Bonf.'='#A5AFB8', 'BY<0.05'='#417D95', 'Bonf.<0.05'='#B4604C')
sig_labels <- c('> BY & Bonf.'='Not significant', 'BY<0.05'='BY only', 'Bonf.<0.05'='Bonferroni')
MASTER_COLORS <- c('Environmental chemicals'='#5989A5', 'Tobacco'='#B97A61',
  'Nutritional biomarkers'='#9A83AC', 'Dietary intake'='#659B8A',
  'Supplements'='#C5A265', 'Health behaviors'='#6D9EAE',
  'Socioeconomic factors'='#B47D91')

study_theme <- function() {
  theme_bw(base_size=12) + theme(
    panel.grid.major=element_line(color='#EDF0F2',linewidth=.25),
    panel.grid.minor=element_blank(),
    panel.border=element_rect(color='#7D8991',fill=NA,linewidth=.45),
    axis.text=element_text(color=study_colors[['ink']]),
    axis.title=element_text(color=study_colors[['ink']]),
    legend.position='bottom',legend.title=element_blank(),
    legend.key=element_rect(fill='white',color=NA),
    legend.text=element_text(size=11),
    plot.title=element_text(size=13,face='bold',color=study_colors[['ink']]),
    plot.tag=element_text(size=15,face='bold'),
    plot.margin=margin(9,12,9,9))
}
study_sig_color <- function() {
  scale_color_manual(values=sig_colors,breaks=names(sig_colors),labels=unname(sig_labels),drop=FALSE)
}
study_sig_fill <- function() {
  scale_fill_manual(values=sig_colors,breaks=names(sig_colors),labels=unname(sig_labels),drop=FALSE)
}
study_context_fill <- function() {
  scale_fill_manual(values=c(red=study_colors[['blue']],black=study_colors[['pale']]))
}
