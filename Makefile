SHELL := /bin/bash
ARCHIVE ?= /var/lib/docker/volumes/aleph_archive-data/_data
POSTGRES ?= postgresql://aleph:aleph@127.0.0.1:15432
ELASTIC ?= http://127.0.0.1:19200
OUTPUT ?= dumps
OUTPUT_PATH=$(OUTPUT)/$(COLLECTION_ID)

all: clean install init dump

init:
	mkdir -p $(OUTPUT_PATH)/elastic
	mkdir -p $(OUTPUT_PATH)/archive

dump: psqldump esdump archivedump
	echo "Dump for $(COLLECTION_ID) finished."
	echo "Documents: `tail +2 $(OUTPUT_PATH)/document.csv | wc -l`"
	echo "Entities: `wc -l $(OUTPUT_PATH)/entities.jsonl`"
	echo "Files in archive: `find $(OUTPUT_PATH)/archive -type f | wc -l`"

esdump: entity.esdump collection.esdump
	cat $(OUTPUT_PATH)/elastic/* | sort > $(OUTPUT_PATH)/entities.jsonl
	rm -rf $(OUTPUT_PATH)/elastic

psqldump: document.psqldump entity.psqldump mapping.psqldump
	psql $(POSTGRES) -c 'copy (select * from collection where id = $(COLLECTION_ID) order by id) to stdout csv header' > $(OUTPUT_PATH)/collection.csv

archivedump:
	for chash in `tail +2 $(OUTPUT_PATH)/document.csv | cut -d, -f4`  ; do \
			path=$${chash:0:2}/$${chash:2:2}/$${chash:4:2} ; \
			source=$(ARCHIVE)/$$path/$$chash ; \
			target=$(OUTPUT_PATH)/archive/$$path/ ; \
			mkdir -p $$target ; \
			cp -r $$source $$target ; \
			echo "Copied $$source to $$target/$$chash" ; \
	done


%.esdump:
	./node_modules/.bin/multielasticdump \
			--direction=dump \
			--input=$(ELASTIC) \
			--output=$(OUTPUT_PATH)/elastic \
			--match='^aleph-$*-' \
			--includeType='data' \
			--searchbody='{"query": {"term": {"collection_id": $(COLLECTION_ID)}}}'

%.psqldump:
	psql $(POSTGRES) -c 'copy (select * from $* where collection_id = $(COLLECTION_ID) order by id) to stdout csv header' > $(OUTPUT_PATH)/$*.csv

install:
	npm i elasticdump

clean:
	rm -rf node_modules
	rm -rf package-lock.json
	rm -rf $(OUTPUT)
