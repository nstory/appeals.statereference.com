JEKYLL ?= bundle exec jekyll

.PHONY: all build serve clean

all: build

build:
	$(JEKYLL) build

serve:
	$(JEKYLL) serve --watch

clean:
	rm -rf _site .jekyll-cache .jekyll-metadata
