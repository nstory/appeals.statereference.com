SEARCH_DIR ?= input/searches
DOWNLOAD_DIR ?= input/downloads
TEXT_DIR ?= input/text
CHROME_PROFILE ?= chrome-profile
OUTPUT_DIR ?= output
R2_REMOTE ?= r2
# shared with ~/src/ethics; everything here goes under appeals/
R2_BUCKET ?= ethics-files
# where appeals/ in the bucket is served
R2_URL ?= https://ethics-files.nathanielstory.com/appeals

.PHONY: searches downloads text clean-text $(OUTPUT_DIR)/cases.jsonl r2-sync r2-sync-dry-run check-r2-bucket all clean

clean:
	rm -f $(OUTPUT_DIR)/cases.jsonl

all: searches downloads text $(OUTPUT_DIR)/cases.jsonl

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

# one line per case in the searches, with links to its PDFs on AppealsWeb
# and their text
$(OUTPUT_DIR)/cases.jsonl:
	bundle exec ruby lib/cases_jsonl.rb --search-dir $(SEARCH_DIR) --download-dir $(DOWNLOAD_DIR) --text-dir $(TEXT_DIR) --r2-url $(R2_URL) --output $@

# Upload $(DOWNLOAD_DIR) to appeals/ in the R2 bucket, so input/downloads/nnn/xxx.pdf
# lands at appeals/nnn/xxx.pdf.  Needs an `r2` rclone remote.  --size-only
# because R2 doesn't keep the local mtimes; rclone sync deletes what's no
# longer local.  Only appeals/ is synced, so the rest of the bucket (ethics'
# disclosures/) is left alone.  nnn.part/ is a download in progress.
R2_SYNC = rclone sync $(DOWNLOAD_DIR) $(R2_REMOTE):$(R2_BUCKET)/appeals \
	  --exclude "*.part/**" --exclude ".DS_Store" \
	  --size-only --transfers 16 --checkers 32 --fast-list --stats-one-line --progress \
	  --header-upload "Cache-Control: public, max-age=31536000, immutable"

check-r2-bucket:
	@test -n "$(R2_BUCKET)" || { echo "R2_BUCKET isn't set"; exit 1; }

# guard: a missing or partial directory would delete PDFs from the bucket
R2_MIN_FILES ?= 24910
r2-sync: check-r2-bucket
	@n=$$(find $(DOWNLOAD_DIR) -type f ! -path "*.part/*" ! -name .DS_Store 2>/dev/null | wc -l | tr -d " "); \
	  test "$$n" -ge $(R2_MIN_FILES) || \
	  { echo "$(DOWNLOAD_DIR) has $$n files, expected at least $(R2_MIN_FILES)"; exit 1; }
	$(R2_SYNC)

# What would `make r2-sync` upload and delete?
r2-sync-dry-run: check-r2-bucket
	$(R2_SYNC) --dry-run
