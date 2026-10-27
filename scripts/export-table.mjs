import fs from 'node:fs/promises';
import { FileBlob, SpreadsheetFile } from '@oai/artifact-tool';

process.on('uncaughtException', error => { console.error(error.message); process.exit(1); });
process.on('unhandledRejection', error => { console.error(error.message); process.exit(1); });

const [input, output, preview, range] = process.argv.slice(2);
const book = await SpreadsheetFile.importXlsx(await FileBlob.load(input));
const sheet = book.worksheets.getItemAt(0);
book.recalculate();
const summary = await book.inspect({kind: 'table', sheetId: sheet.name,
  range, maxChars: 600, tableMaxRows: 3, tableMaxCols: 4});
console.log(summary.ndjson);
if (preview) {
  const picture = await book.render({sheetName: sheet.name, range, scale: 1, format: 'png'});
  await fs.writeFile(preview, new Uint8Array(await picture.arrayBuffer()));
}
await (await SpreadsheetFile.exportXlsx(book)).save(output);
console.log(`Exported ${sheet.name}`);
