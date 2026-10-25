# Build the site, then index it.  lib/search_index.mjs builds the Pagefind
# index from etl/output/cases.jsonl, not from the site, but writes its bundle
# to _site/pagefind -- and `jekyll build` empties _site, so it still has to run
# after Jekyll, which is why this isn't two independent targets.  Pagefind
# never deletes a previous run's files, and keep_files (see reindex) spares
# _site/pagefind from Jekyll, so each indexing clears it first; left alone,
# stale fragments pile up.
JEKYLL ?= bundle exec jekyll
WRANGLER ?= npx wrangler@4.152.0

.PHONY: all build index reindex serve deploy login clean

all: build

build: index

index:
	$(JEKYLL) build
	rm -rf _site/pagefind
	node lib/search_index.mjs

# _config.yml's keep_files holds onto _site/pagefind across the regenerations
# watching does, so edits leave search working against the index built above.
# The index only goes stale when etl/output/cases.jsonl changes; `make reindex`
# refreshes it in place, from another shell, without stopping the server.
reindex:
	rm -rf _site/pagefind
	node lib/search_index.mjs

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
