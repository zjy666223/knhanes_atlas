"""Keep the Shiny and static publication browsers on the same catalog."""
from pathlib import Path
from hashlib import sha256
from html import escape
import json
import re

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / 'site/research'


def build():
    catalog = json.loads((SITE / 'publications.json').read_text())
    figures, tables = catalog['figures'], catalog['tables']
    version = sha256((SITE / 'publications.json').read_bytes()).hexdigest()[:16]
    contents = []
    for group in ['Main figures', 'Extended Data figures', 'Supplementary figures', 'Tables', 'Supplementary tables']:
        items = [item for item in figures + tables if item['group'] == group]
        contents.append(f'<h2>{group}</h2><ul>' + ''.join(
            f'<li><a href="#{item["id"]}" title="{escape(item["title"], quote=True)}">{item["label"]}</a></li>' for item in items) + '</ul>')
    downloads = '<ul>' + ''.join(f'<li><a href="{escape(item["file"], quote=True)}" download="{item["source_file"]}">{item["label"]}</a></li>' for item in figures + tables) + '</ul>'
    page = (ROOT / 'scripts/publications.html').read_text()
    for kind in ['css', 'js']:
        data = (ROOT / f'scripts/publications.{kind}').read_bytes()
        (SITE / f'publications.{kind}').write_bytes(data)
        page = page.replace('__STYLE_VERSION__' if kind == 'css' else '__SCRIPT_VERSION__', sha256(data).hexdigest()[:16])
    page = page.replace('__MANIFEST_VERSION__', version).replace('__CONTENTS__', ''.join(contents)).replace('__DOWNLOADS__', downloads)
    assert not re.search(r'__[A-Z_]+__', page)
    (SITE / 'index.html').write_text(page)
    (ROOT / 'src/data/figures.json').write_text(json.dumps([{**item, 'title': item['label'] + ' · ' + item['title']} for item in figures], ensure_ascii=False, indent=2))
    (ROOT / 'src/data/tables.json').write_text(json.dumps(tables, ensure_ascii=False, indent=2))
    path = ROOT / 'src/app.R'
    app = path.read_text()
    if 'table_files <-' not in app:
        app = app.replace('figure_files <- jsonlite::fromJSON("data/figures.json")', 'figure_files <- jsonlite::fromJSON("data/figures.json")\ntable_files <- jsonlite::fromJSON("data/tables.json")')
    app = app.replace('h1("Results and figure downloads")', 'h1("Results, figures and tables")')
    if 'Browse all figures and tables' not in app:
        app = app.replace('    h3("Study figures"),', '    p(a("Browse all figures and tables", href="research/index.html", target="_blank")),\n    h3("Study figures"),')
    workbook = catalog['workbook']
    table_ui = f'''    # Publication tables begin
    h3("Study tables"),
    p(a("Download complete workbook", href="research/{workbook['file']}?v={workbook['sha256'][:16]}", download="Supplementary_Tables_KNHANES.xlsx")),
    selectInput("publication_table", "Select a table", choices=setNames(seq_len(nrow(table_files)), paste(table_files$label, table_files$title, sep=" · "))),
    uiOutput("publication_table_preview"),
    # Publication tables end
'''
    if '# Publication tables begin' in app:
        app = re.sub(r'    # Publication tables begin[\s\S]*?    # Publication tables end\n', lambda _: table_ui, app)
    else:
        app = app.replace('    h3("Joint exposure models")', table_ui + '    h3("Joint exposure models")')
    preview = '''  output$figure_preview <- renderUI({
    req(input$figure)
    f <- figure_files[as.integer(input$figure),]
    href <- paste0("research/", f$file, "?v=", substr(f$sha256, 1, 16))
    label <- if (grepl("\\\\.pdf$", f$source_file, ignore.case=TRUE)) "Download PDF" else "Download PNG"
    tagList(p(a(label, href=href, download=f$source_file), " · ", a("Open full resolution", href=href, target="_blank")),
      a(href=href, target="_blank", img(`data-atlas-src`=paste0("research/", f$preview, "?v=", substr(f$preview_sha256, 1, 16)), alt=f$title, style="max-width:100%;height:auto;")),
      lapply(f$legend[[1]], p))
  })
'''
    app, count = re.subn(r'  output\$figure_preview <- renderUI\(\{[\s\S]*?\n  \}\)\n', lambda _: preview, app)
    assert count == 1
    table_server = f'''  # Publication table server begin
  output$publication_table_preview <- renderUI({{
    req(input$publication_table)
    t <- table_files[as.integer(input$publication_table),]
    tagList(p(a("Download Excel", href=paste0("research/", t$file, "?v=", substr(t$sha256, 1, 16)), download=t$source_file), " · ",
      a("Open table preview", href=paste0("research/index.html?v={version}#", t$id), target="_blank")),
      tags$iframe(`data-atlas-src`=paste0("research/index.html?embedded=1&v={version}#", t$id), title=t$label,
        style="width:100%;height:800px;border:0;", loading="lazy"))
  }})
  # Publication table server end
'''
    if '# Publication table server begin' in app:
        app = re.sub(r'  # Publication table server begin[\s\S]*?  # Publication table server end\n', lambda _: table_server, app)
    else:
        app = app.replace('  output$joint_table <-', table_server + '  output$joint_table <-')
    app = re.sub(r'research/figures/10_研究流程.png(?:\?v=[a-f0-9]+)?"', f'research/figures/10_研究流程.png?v={figures[0]["sha256"][:16]}"', app)
    path.write_text(app)
    path = ROOT / 'src/R/vibration.R'
    vibration = path.read_text().replace('Download Extended Data Figure 4', 'Download Extended Data Figure 5').replace("download='Figure Extended 4_v1.pdf'", "download='Figure Extended 5.pdf'")
    voe = next(item for item in figures if item['id'] == 'extended-5')
    vibration = re.sub(r"href='research/figures/11_效应振动.pdf(?:\?v=[a-f0-9]+)?'", f"href='research/figures/11_效应振动.pdf?v={voe['sha256'][:16]}'", vibration)
    path.write_text(vibration)
    print('Publication browser and Shiny links updated: 20 figures, 17 tables.')


if __name__ == '__main__':
    build()
