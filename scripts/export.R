args <- commandArgs(FALSE)
script <- sub('^--file=', '', args[grepl('^--file=', args)])
root <- dirname(dirname(normalizePath(script)))
.libPaths(c(file.path(root,'work/rlib'), .libPaths()))
library(shinylive)
# Keep the exporter cache inside this project, including on macOS.
cache <- file.path(root,'work/cache/shinylive')
dir.create(cache, recursive=TRUE, showWarnings=FALSE)
assignInNamespace('assets_cache_dir', local({path <- cache; function() path}), ns='shinylive')
shinylive::assets_ensure()
shinylive::export(file.path(root,'src'), file.path(root,'site'),
  wasm_packages=TRUE, package_cache=TRUE, max_filesize='90M', quiet=FALSE,
  template_params=list(title='KNHANES Atlas', include_in_head=paste0(
    '<script>window.knhanesSiteRoot=new URL(".",window.location.href).href;</script>',
    '<meta name="description" content="KNHANES 2007–2024 phenome–exposome atlas and vibration of effects.">')))
file.create(file.path(root,'site/.nojekyll'))
