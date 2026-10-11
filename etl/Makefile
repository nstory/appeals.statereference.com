SEARCH_DIR ?= input/searches
CHROME_PROFILE ?= chrome-profile

.PHONY: searches

# Search AppealsWeb for every day the files in $(SEARCH_DIR) don't cover yet,
# newest first; see lib/searches.rb.  Safe to run daily.  Opens a Chrome
# window, and if Imperva wants a security check, waits for you to pass it
# there.  SEARCH_FLAGS takes --max N to cap the number of searches and
# --dry-run to list them.
searches:
	bundle exec ruby lib/searches.rb --search-dir $(SEARCH_DIR) --profile-dir $(CHROME_PROFILE) $(SEARCH_FLAGS)
