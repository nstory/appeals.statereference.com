// Builds the Pagefind index straight from etl/output/cases.jsonl, one record
// per case, and writes the bundle to _site/pagefind.  There are no pages to
// crawl: each record's url is the case's detail page on AppealsWeb, so a
// search result links directly to it.  (Its PDFs can't be linked to for
// reading: AppealsWeb serves them as attachments.)
//
//   node lib/search_index.mjs
//
// Every field search.js displays is in meta.  type, sub_type and year are the
// filters, and date the only sort key.  date is when the case closed, or for
// the few still open, when it opened; year is its first four characters.
//
// content leads with the requester and custodian, so a search for either finds
// every case of theirs -- including the few with no determination text yet.

import { createReadStream } from "node:fs";
import { createInterface } from "node:readline";
import * as pagefind from "pagefind";

const { index, errors: createErrors } = await pagefind.createIndex();
if (!index) throw new Error(`pagefind: ${createErrors.join("; ")}`);

// Pagefind drops an empty meta or sort value rather than storing "", and a
// missing one is what search.js already expects of a field we don't have.
function present(fields) {
  return Object.fromEntries(Object.entries(fields).filter(([, v]) => v != null && v !== ""));
}

const lines = createInterface({ input: createReadStream("../etl/output/cases.jsonl") });
let count = 0;
for await (const line of lines) {
  const appeal = JSON.parse(line);
  const date = appeal.closed ?? appeal.opened;
  // Meta values are strings, so the PDFs go in as JSON for search.js to parse.
  const pdfs = appeal.pdfs.map(({ url, filename }) => ({ url, filename }));

  const { errors } = await index.addCustomRecord({
    url: appeal.detail_url,
    content: [appeal.requester, appeal.custodian, appeal.fulltext].filter(Boolean).join("\n\n"),
    language: "en",
    meta: present({
      case_no: appeal.case_no,
      requester: appeal.requester,
      custodian: appeal.custodian,
      type: appeal.type,
      sub_type: appeal.sub_type,
      status: appeal.status,
      date,
      pdfs: pdfs.length ? JSON.stringify(pdfs) : null,
    }),
    filters: {
      type: [appeal.type],
      sub_type: [appeal.sub_type],
      ...(date ? { year: [date.slice(0, 4)] } : {}),
    },
    sort: present({ date }),
  });
  if (errors.length) throw new Error(`pagefind: ${appeal.case_no}: ${errors.join("; ")}`);
  count++;
}

const { errors } = await index.writeFiles({ outputPath: "_site/pagefind" });
if (errors.length) throw new Error(`pagefind: ${errors.join("; ")}`);
await pagefind.close();
console.log(`Indexed ${count} cases into _site/pagefind`);
