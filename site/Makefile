# Build the site and its search index.  lib/search_index.mjs builds the
# Pagefind index from etl/output/cases.jsonl, not from the site, and writes its
# bundle to _site/pagefind, which keep_files (see _config.yml) spares from
# Jekyll -- so the index is its own target, rebuilt only when its inputs
# change.  Pagefind never deletes a previous run's files, so each indexing
# clears _site/pagefind first; left alone, stale fragments pile up.
JEKYLL ?= bundle exec jekyll
WRANGLER ?= npx wrangler@4.152.0

.PHONY: all build index reindex serve deploy login clean

all: build

CASES ?= ../etl/output/cases.jsonl
# Pagefind always writes this, so it stands in for the whole index.
PAGEFIND_ENTRY = _site/pagefind/pagefind-entry.json

build: index
	$(JEKYLL) build

index: $(PAGEFIND_ENTRY)

# package-lock.json is here for Pagefind upgrades.
$(PAGEFIND_ENTRY): $(CASES) lib/search_index.mjs package-lock.json
	rm -rf _site/pagefind
	node lib/search_index.mjs

# keep_files also holds onto _site/pagefind across the regenerations `jekyll
# serve --watch` does, so edits leave search working.  `make reindex` forces a
# rebuild in place, from another shell, without stopping the server.
reindex:
	$(MAKE) -B $(PAGEFIND_ENTRY)

serve: build
	$(JEKYLL) serve --skip-initial-build --watch

# The Pages project is "appeals"; Cloudflare served it at appeals-94g.pages.dev
# because appeals.pages.dev was taken.
deploy: build
	$(WRANGLER) pages deploy _site --project-name appeals

login:
	$(WRANGLER) login

clean:
	rm -rf _site .jekyll-cache .jekyll-metadata
