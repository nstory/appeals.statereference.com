// The search box, and -- on /search/ -- the results it produces, backed by the
// Pagefind index that lib/search_index.mjs builds from etl/output/cases.jsonl.
// Each result's url is the case's detail page on AppealsWeb, so the results
// link straight to it.
//
// Both pages that render the form load this.  The form behaves the same on each
// one; the difference is where a search goes.  /search/ has the results shell,
// so it answers the search itself and pushes a history entry.  The homepage has
// no shell, so the URL it builds is a real navigation to /search/.
//
// Pagefind returns the whole result set from one search() call, as stubs whose
// data() is fetched lazily.  Paging is therefore just a slice of that array --
// no re-querying, and results.length is an exact total rather than an estimate.

const PAGE_SIZE = 20;
const PAGE_WINDOW = 2; // page links shown either side of the current one

// What the sort control offers, and what each option means to Pagefind.  A
// sort replaces relevance ranking rather than refining it -- Pagefind will do
// one or the other -- so "relevance" is the absence of a sort, not a key of
// its own.  The key is date -- when the case closed -- indexed by
// lib/search_index.mjs.
const SORTS = {
  relevance: null,
  newest: { date: "desc" },
  oldest: { date: "asc" },
};

const summaryEl = document.querySelector("[data-search-summary]");
const resultsEl = document.querySelector("[data-search-results]");
const pagerEl = document.querySelector("[data-search-pagination]");
const form = document.querySelector("[data-search-form]");
const input = document.querySelector("[data-search-input]");
const sortWrap = document.querySelector("[data-sort]");
const sortSelect = document.querySelector("[data-sort-select]");

// The sidebar's filters, which only /search/ has: one fieldset per Pagefind
// filter, named in data-filter, which is also its URL parameter.  Each
// checkbox carries the URL slug as its value, the exact Pagefind filter value
// in data-value and, where that isn't fit to show, a label in data-label.
// `scope` is how the summary line phrases a selection, given its labels.
const FACETS = [
  { name: "type", scope: (labels) => ` of type ${labels.join(" or ")}` },
  { name: "sub_type", scope: (labels) => ` at ${labels.join(" or ")}` },
  { name: "year", scope: (labels) => ` from ${labels.join(" or ")}` },
].map((facet) => {
  const fieldset = document.querySelector(`[data-filter="${facet.name}"]`);
  return {
    ...facet,
    fieldset,
    clearButton: fieldset?.querySelector("[data-filter-clear]"),
    boxes: [...(fieldset?.querySelectorAll("[data-value]") ?? [])],
  };
});
// On a phone the sidebar is a closed drawer, so the button that opens it
// carries the number ticked -- otherwise nothing on screen says a filter is on.
const badge = document.querySelector("[data-filter-badge]");

// The results shell, which only /search/ has.  Everything above is on both
// pages; these three are what let this one answer a search rather than send it.
const hasResults = Boolean(summaryEl && resultsEl && pagerEl);

// Where a search lands.  The form's action is /search/ on both pages -- which
// on /search/ is the page itself -- so urlFor builds the same string either way
// and the pager and history entries can use it too.
const target = form?.getAttribute("action") ?? location.pathname;

let pagefindPromise = null;
let cache = { key: null, results: [], counts: {} };
// Bumped on every new search so a slow one that lands after a newer one can
// tell it's stale and bail out instead of overwriting the newer results.
let token = 0;

function getPagefind() {
  // Cache the promise, not the module: init() and filters() have to finish
  // before anyone searches, and preload() races search() for this call.
  // filters() is what makes Pagefind return counts alongside each search.
  pagefindPromise ??= (async () => {
    const api = await import(form.dataset.pagefindBundle);
    await api.init();
    await api.filters();
    return api;
  })();
  return pagefindPromise;
}

function readUrl() {
  const params = new URLSearchParams(location.search);
  const page = parseInt(params.get("page") ?? "1", 10);
  // Selecting through the sidebar's own order drops unknown slugs and
  // duplicates, so a hand-edited URL can't produce a selection it can't show.
  const filters = {};
  for (const { name, boxes } of FACETS) {
    const slugs = new Set((params.get(name) ?? "").split(","));
    filters[name] = boxes.filter((box) => slugs.has(box.value)).map((box) => box.dataset.value);
  }
  const sort = params.get("sort");
  return {
    query: (params.get("q") ?? "").trim(),
    filters,
    // hasOwn, not `in`: `?sort=toString` would otherwise name a real key.
    sort: Object.hasOwn(SORTS, sort) ? sort : "relevance",
    page: Number.isFinite(page) && page > 0 ? page : 1,
  };
}

// Takes a whole state -- {query, filters, sort, page}, where filters maps each
// facet's name to its selected values -- since every control changes one
// field of it and leaves the rest alone.
function urlFor({ query, filters, sort, page }) {
  const params = new URLSearchParams();
  if (query) params.set("q", query);
  for (const { name, boxes } of FACETS) {
    const chosen = boxes.filter((box) => filters[name]?.includes(box.dataset.value));
    if (chosen.length) params.set(name, chosen.map((box) => box.value).join(","));
  }
  if (sort !== "relevance") params.set("sort", sort);
  if (page > 1) params.set("page", String(page));
  const search = params.toString();
  return search ? `${target}?${search}` : target;
}

// Identifies a result set, so paging within one doesn't re-run the search.
// Sort is part of it: Pagefind orders the set as it builds it, so a different
// order is a different search rather than a re-arrangement of this one.
function cacheKey({ query, filters, sort }) {
  return JSON.stringify([filters, sort, query]);
}

// " of type Appeal or Fee Petition from 2024" -- each filter ORs within itself,
// so "or" is what a multiple selection actually means, and the filters AND with
// each other.
function scope(filters) {
  return FACETS.map(({ name, scope, boxes }) => {
    const labels = boxes
      .filter((box) => filters[name].includes(box.dataset.value))
      .map((box) => box.dataset.label ?? box.dataset.value);
    return labels.length ? scope(labels) : "";
  }).join("");
}

// The Pagefind filters for a selection, leaving out `except`: a facet's counts
// come from a search filtered by every facet but itself.
function pagefindFilters(filters, except = null) {
  const out = {};
  for (const { name } of FACETS) {
    if (name !== except && filters[name].length) out[name] = { any: filters[name] };
  }
  return out;
}

function pageNumbers(current, total) {
  const wanted = new Set([1, total, current]);
  for (let i = 1; i <= PAGE_WINDOW; i++) {
    wanted.add(current - i);
    wanted.add(current + i);
  }
  const shown = [...wanted].filter((n) => n >= 1 && n <= total).sort((a, b) => a - b);

  const out = [];
  let previous = 0;
  for (const n of shown) {
    if (previous && n - previous > 1) out.push(null); // gap -> ellipsis
    out.push(n);
    previous = n;
  }
  return out;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// "Jan 4, 2026".  Split by hand rather than through Date, which reads
// "2026-01-04" as UTC midnight and so shows it as Jan 3 anywhere west of
// Greenwich.
function formatDate(iso) {
  if (!iso) return null;
  const [year, month, day] = iso.split("-");
  return `${MONTHS[Number(month) - 1]} ${Number(day)}, ${year}`;
}

// "SPR26/4203", as the determinations cite a case, from AppealsWeb's
// "20264203".
function caseNumber(caseNo) {
  return /^20\d{6}$/.test(caseNo ?? "") ? `SPR${caseNo.slice(2, 4)}/${caseNo.slice(4)}` : caseNo;
}

// Stage labels by sub_type, from the sidebar, so the results name a stage as
// it does.
const STAGES = Object.fromEntries(
  [...document.querySelectorAll('[data-filter="sub_type"] [data-label]')].map((box) => [
    box.dataset.value,
    box.dataset.label,
  ]),
);

function parsePdfs(json) {
  try {
    return JSON.parse(json ?? "[]");
  } catch {
    return [];
  }
}

// `excerpting` is off when there's no query: Pagefind falls back to the start of
// the record, which is the requester and custodian the heading and details line
// already show.
function resultItem(result, excerpting) {
  const meta = result.meta ?? {};
  const li = document.createElement("li");
  li.className = "py-3 border-bottom";

  const heading = document.createElement("h2");
  heading.className = "h6 mb-1";
  const link = document.createElement("a");
  link.href = result.url;
  link.textContent = meta.custodian || caseNumber(meta.case_no) || result.url;
  heading.append(link);
  li.append(heading);

  // The date leads, so a column of results scans by date.  A stage is only
  // worth naming when it isn't the initial one, which nearly every case is.
  const stage = meta.sub_type && meta.sub_type !== "Initial" ? STAGES[meta.sub_type] ?? meta.sub_type : null;
  const kind = [meta.type, stage?.toLowerCase()].filter(Boolean).join(", ");
  const details = [
    meta.status === "Open" ? `Opened ${formatDate(meta.date)}` : formatDate(meta.date),
    caseNumber(meta.case_no),
    kind,
    meta.requester && `Requester ${meta.requester}`,
  ].filter(Boolean);
  const pdfs = parsePdfs(meta.pdfs);
  if (details.length || pdfs.length) {
    const line = document.createElement("p");
    line.className = `small text-body-secondary ${excerpting ? "mb-1" : "mb-0"}`;
    line.textContent = details.join(" · ");
    // AppealsWeb serves the PDFs as downloads, so these download rather than
    // open; the heading's detail page is where to read about the case.
    for (const pdf of pdfs) {
      if (line.childNodes.length) line.append(" · ");
      const a = document.createElement("a");
      a.href = pdf.url;
      a.textContent = pdf.filename || "PDF";
      line.append(a);
    }
    li.append(line);
  }

  if (excerpting) {
    const excerpt = document.createElement("p");
    excerpt.className = "small mb-0";
    // Pagefind escapes the record's text when it builds the excerpt and adds
    // only <mark> around the matched terms, so this is markup we generated, not
    // the determination's text.
    excerpt.innerHTML = result.excerpt;
    li.append(excerpt);
  }

  return li;
}

// Point the sidebar at the current selection.
function renderFilters(filters) {
  let ticked = 0;
  for (const { name, boxes, clearButton } of FACETS) {
    for (const box of boxes) box.checked = filters[name].includes(box.dataset.value);
    clearButton?.classList.toggle("d-none", filters[name].length === 0);
    ticked += filters[name].length;
  }
  if (badge) {
    badge.textContent = String(ticked);
    badge.hidden = ticked === 0;
  }
}

// `counts` maps each facet to the number of results each of its values would
// give for the current search and the other facets' selections, whatever else
// is ticked in this one -- the number a reader is weighing when deciding what
// to tick.  A value missing from a facet's counts has no results.
function renderCounts(counts) {
  for (const { name, boxes } of FACETS) {
    for (const box of boxes) {
      const label = box.closest("label");
      const n = counts[name] ? (counts[name][box.dataset.value] ?? 0) : null;
      label.querySelector("[data-filter-count]").textContent = n?.toLocaleString() ?? "";
      // A dead end stays visible but unpickable.  A checked box always stays
      // pickable, or there'd be no way to undo it.
      box.disabled = n === 0 && !box.checked;
      label.classList.toggle("opacity-50", box.disabled);
    }
  }
}

// The control is no use with nothing to reorder, and next to the empty-state
// prompt it reads as something that ought to be doing more than it is.
function showSort(visible) {
  sortWrap?.classList.toggle("d-none", !visible);
}

function renderPager(state, totalPages) {
  const { page } = state;
  pagerEl.replaceChildren();
  if (totalPages <= 1) return;

  const list = document.createElement("ul");
  list.className = "pagination";

  const item = (label, targetPage, { disabled = false, current = false } = {}) => {
    const li = document.createElement("li");
    li.className = `page-item${disabled ? " disabled" : ""}${current ? " active" : ""}`;

    const el = document.createElement(disabled ? "span" : "a");
    el.className = "page-link";
    el.textContent = label;
    if (!disabled) {
      el.href = urlFor({ ...state, page: targetPage });
    }
    if (current) el.setAttribute("aria-current", "page");
    li.append(el);
    list.append(li);
  };

  item("Previous", page - 1, { disabled: page === 1 });
  for (const n of pageNumbers(page, totalPages)) {
    if (n === null) item("…", 0, { disabled: true });
    else item(String(n), n, { current: n === page });
  }
  item("Next", page + 1, { disabled: page === totalPages });

  pagerEl.append(list);
}

async function renderPage(state) {
  const { query, filters } = state;
  const total = cache.results.length;
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  if (state.page > totalPages) {
    // ?page= past the end shows the last page; correct the URL to match, without
    // adding a history entry for a page the reader never asked for.
    state = { ...state, page: totalPages };
    history.replaceState({}, "", urlFor(state));
  }

  // Without a query the reader is browsing rather than searching, so the summary
  // drops the "for ..." and counts cases -- there was no search for them to be
  // the result of.
  const forQuery = query ? ` for ${query}` : "";
  const noun = query ? "result" : "case";

  if (total === 0) {
    summaryEl.textContent = `No ${noun}s${forQuery}${scope(filters)}.`;
    resultsEl.replaceChildren();
    pagerEl.replaceChildren();
    showSort(false);
    return;
  }

  const first = (state.page - 1) * PAGE_SIZE;
  const stubs = cache.results.slice(first, first + PAGE_SIZE);

  const mine = token;
  const results = await Promise.all(stubs.map((stub) => stub.data()));
  if (mine !== token) return;

  summaryEl.textContent =
    `${total.toLocaleString()} ${total === 1 ? noun : `${noun}s`}${forQuery}${scope(filters)} · ` +
    `showing ${(first + 1).toLocaleString()}–${(first + results.length).toLocaleString()}`;
  resultsEl.replaceChildren(...results.map((result) => resultItem(result, Boolean(query))));
  renderPager(state, totalPages);
  showSort(true);
}

async function render() {
  const state = readUrl();
  const { query, filters, sort } = state;
  if (input && input.value !== query) input.value = query;
  renderFilters(filters);
  if (sortSelect) sortSelect.value = sort;

  const key = cacheKey(state);
  if (key !== cache.key) {
    const mine = ++token;
    summaryEl.textContent = query ? `Searching for ${query}…` : "Loading cases…";
    resultsEl.replaceChildren();
    pagerEl.replaceChildren();

    let search;
    const counts = {};
    try {
      const api = await getPagefind();
      // A null term filters without searching.  With a filter that means
      // browse every case of that kind; with nothing at all it means browse
      // the lot, which is what /search/ opens on.
      search = await api.search(query || null, {
        filters: pagefindFilters(filters),
        sort: SORTS[sort] ?? {},
      });
      // Each facet's counts come from the `filters` of a search filtered by
      // every other facet but not by itself, so they're what ticking each value
      // would give.  Not from totalFilters: for a quoted phrase Pagefind counts
      // totalFilters before it checks the phrase, so a quoted phrase's counts
      // ran far higher than ticking gave.  A facet with nothing
      // ticked is filtered by the other facets alone already, so the main
      // search's counts serve.
      for (const { name } of FACETS) {
        const others = filters[name].length
          ? await api.search(query || null, { filters: pagefindFilters(filters, name) })
          : search;
        counts[name] = others.filters?.[name] ?? null;
      }
    } catch (error) {
      console.error("[search] Pagefind failed to load or search", error);
      summaryEl.textContent = "Search is unavailable right now.";
      return;
    }
    if (mine !== token) return;
    cache = { key, results: search.results, counts };
  }

  renderCounts(cache.counts);
  await renderPage(state);
}

function go(url, { replace = false } = {}) {
  if (replace) history.replaceState({}, "", url);
  else history.pushState({}, "", url);
  return render();
}

// The state the controls are currently showing, which is what the reader has
// typed but may not have submitted -- so picking a filter or a sort applies
// it to the query in the box rather than to the last one searched.  Any change
// to the result set starts again at page 1.  The homepage has no boxes, so a
// search from there starts unfiltered.
function pending() {
  return {
    query: input.value.trim(),
    filters: Object.fromEntries(
      FACETS.map(({ name, boxes }) => [name, boxes.filter((box) => box.checked).map((box) => box.dataset.value)]),
    ),
    sort: sortSelect?.value ?? "relevance",
    page: 1,
  };
}

// Submitting means "show me this".  On /search/ that's a re-render in place;
// on the homepage it's the trip to /search/ the form would have made on its
// own.
function submit(url) {
  if (hasResults) return go(url);
  location.assign(url);
}

form?.addEventListener("submit", (event) => {
  event.preventDefault();
  submit(urlFor(pending()));
});

sortSelect?.addEventListener("change", () => go(urlFor(pending())));

for (const { name, fieldset, clearButton } of FACETS) {
  fieldset?.addEventListener("change", () => go(urlFor(pending())));
  clearButton?.addEventListener("click", () => {
    const state = pending();
    go(urlFor({ ...state, filters: { ...state.filters, [name]: [] } }));
  });
}

// Warm the indexes while the user is still typing; search() then has less to
// fetch when they hit enter.
input?.addEventListener("input", () => {
  const value = input.value.trim();
  if (value) getPagefind().then((api) => api.preload(value)).catch(() => {});
});

if (hasResults) {
  pagerEl.addEventListener("click", (event) => {
    const link = event.target.closest("a.page-link");
    if (!link || event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
    event.preventDefault();
    go(link.getAttribute("href")).then(() => {
      window.scrollTo({ top: 0 });
      resultsEl.focus();
    });
  });

  window.addEventListener("popstate", render);

  resultsEl.tabIndex = -1;
  render();
}
