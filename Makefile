.PHONY: all
all:
	cd etl && make clean all r2-sync
	cd site && make clean build
