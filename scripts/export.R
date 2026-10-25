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

# The exporter merges old package indexes; only mount current dependencies at startup.
# Retain existing versioned archives for visitors still running the previous build.
metadata_path <- file.path(root,'site/shinylive/webr/packages/metadata.rds')
metadata <- readRDS(metadata_path)
needed <- shinylive:::resolve_dependencies(unique(renv::dependencies(file.path(root,'src'), quiet=TRUE)$Package))
metadata <- metadata[intersect(names(metadata), needed)]
saveRDS(metadata, metadata_path)
jsonlite::write_json(unname(vapply(metadata, function(x) x$path, character(1))),
  file.path(root,'checks/active_packages.json'), pretty=TRUE)
cat('Active browser packages:', length(metadata), '\n')

# Cache immutable runtime assets and refresh the mutable package index separately.
# Patch the pinned upstream worker at build time; leave its app routing intact.
assets <- shinylive:::assets_dir()
worker <- paste(readLines(file.path(assets,'shinylive-sw.js')), collapse='\n')
patch_worker <- function(before, after) {
  stopifnot(grepl(before, worker, fixed=TRUE))
  worker <<- sub(before, after, worker, fixed=TRUE)
}
cache_version <- paste0('knhanes_atlas-', basename(assets), '-', substr(tools::md5sum(metadata_path),1,12))
patch_worker('var useCaching = false;', 'var useCaching = true;')
patch_worker('var version = "v10";', paste0('var version = "',cache_version,'";'))
patch_worker('caches.open(version + cacheName)])', 'caches.open(version + cacheName).catch(() => null)])')
patch_worker('const keys = await caches.keys();', 'const keys = await caches.keys().catch(() => []);')
patch_worker('return key.indexOf(version + cacheName) !== 0;',
  'return key.startsWith("knhanes_atlas-") && key !== version + cacheName;')
patch_worker('if (useCaching) {', 'if (useCaching && !url.pathname.endsWith("/packages/metadata.rds")) {')
patch_worker('const cachedResponse = await caches.match(request);',
  'const cachedResponse = await caches.match(request).catch(() => undefined);')
patch_worker('if (request.url.startsWith(baseUrl + "/shinylive/") || request.url === baseUrl + "/favicon.ico") {',
  'if (networkResponse.ok && (request.url.startsWith(baseUrl + "/shinylive/") || request.url === baseUrl + "/favicon.ico")) {')
patch_worker('const cache = await caches.open(version + cacheName);\n            await cache.put(request, networkResponse.clone());',
  paste0('try {\n              const cache = await caches.open(version + cacheName);\n',
    '              await cache.put(request, networkResponse.clone());\n',
    '            } catch { /* Continue using the network response when storage is unavailable. */ }'))
writeLines(worker, file.path(root,'site/shinylive-sw.js'))

# Render the About panel from the same R source so the early homepage stays current.
setwd(file.path(root,'src'))
app <- new.env(parent=globalenv())
suppressPackageStartupMessages(sys.source('app.R', envir=app))
writeLines(htmltools::renderTags(app$ui)$html, file.path(root,'work/ui.html'))
stopifnot(system2('python3', c('-B', shQuote(file.path(root,'scripts/shell.py')))) == 0L)
