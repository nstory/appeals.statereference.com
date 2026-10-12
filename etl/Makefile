SEARCH_DIR ?= input/searches
DOWNLOAD_DIR ?= input/downloads
TEXT_DIR ?= input/text
CHROME_PROFILE ?= chrome-profile

.PHONY: searches downloads text clean-text

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
