SEARCH_DIR ?= input/searches
DOWNLOAD_DIR ?= input/downloads
TEXT_DIR ?= input/text
CHROME_PROFILE ?= chrome-profile
OUTPUT_DIR ?= output
R2_REMOTE ?= r2
# TBD
R2_BUCKET ?=

.PHONY: searches downloads text clean-text r2-sync r2-sync-dry-run check-r2-bucket

# https://www.sec.state.ma.us/AppealsWeb/AppealsStatus.aspx
# runs searches for determinations based on the date closed
searches:
	bundle exec ruby lib/searches.rb --search-dir $(SEARCH_DIR) --profile-dir $(CHROME_PROFILE) $(SEARCH_FLAGS)

#  download PDFs identified in searches into input/downloads/nnn
downloads:
	bundle exec ruby lib/downloads.rb --search-dir $(SEARCH_DIR) --download-dir $(DOWNLOAD_DIR) --profile-dir $(CHROME_PROFILE) $(DOWNLOAD_FLAGS)

# extract text from input/downloads/nnn/xxx.pdf into input/text/nnn.txt
text:
	bundle exec ruby lib/text.rb --download-dir $(DOWNLOAD_DIR) --text-dir $(TEXT_DIR) $(TEXT_FLAGS)

clean-text:
	rm -rf $(TEXT_DIR) && mkdir -p $(TEXT_DIR)

# Upload $(OUTPUT_DIR)/r2 to the R2 bucket.  Needs an `r2` rclone remote.
# --size-only because R2 doesn't keep the local mtimes; rclone sync deletes
# what's no longer local.
R2_SYNC = rclone sync $(OUTPUT_DIR)/r2 $(R2_REMOTE):$(R2_BUCKET) \
	  --size-only --transfers 16 --checkers 32 --fast-list --stats-one-line --progress \
	  --header-upload "Cache-Control: public, max-age=31536000, immutable"

check-r2-bucket:
	@test -n "$(R2_BUCKET)" || { echo "R2_BUCKET isn't set"; exit 1; }

# guard: an empty or missing directory would empty the bucket
r2-sync: check-r2-bucket
	@test -n "$$(ls -A $(OUTPUT_DIR)/r2 2>/dev/null)" || \
	  { echo "$(OUTPUT_DIR)/r2 is empty"; exit 1; }
	$(R2_SYNC)

# What would `make r2-sync` upload and delete?
r2-sync-dry-run: check-r2-bucket
	$(R2_SYNC) --dry-run
