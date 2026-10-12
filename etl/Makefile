SEARCH_DIR ?= input/searches
DOWNLOAD_DIR ?= input/downloads
CHROME_PROFILE ?= chrome-profile

.PHONY: searches downloads

# Search AppealsWeb for every day the files in $(SEARCH_DIR) don't cover yet,
# newest first; see lib/searches.rb.  Safe to run daily.  Opens a Chrome
# window, and if Imperva wants a security check, waits for you to pass it
# there.  SEARCH_FLAGS takes --max N to cap the number of searches and
# --dry-run to list them.
searches:
	bundle exec ruby lib/searches.rb --search-dir $(SEARCH_DIR) --profile-dir $(CHROME_PROFILE) $(SEARCH_FLAGS)

# Download every PDF the searches in $(SEARCH_DIR) list into
# $(DOWNLOAD_DIR)/nnn/, newest first, skipping ones already there; see
# lib/downloads.rb.  Safe to run daily, after searches.  Uses the same Chrome
# window and security check as searches.  DOWNLOAD_FLAGS takes --max N,
# --delay SECONDS (default 1) and --dry-run.
downloads:
	bundle exec ruby lib/downloads.rb --search-dir $(SEARCH_DIR) --download-dir $(DOWNLOAD_DIR) --profile-dir $(CHROME_PROFILE) $(DOWNLOAD_FLAGS)
