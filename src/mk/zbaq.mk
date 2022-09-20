.SHELLFLAGS = -ec

ZBAQ_PATH:=$(shell readlink -f $(dir $(lastword $(MAKEFILE_LIST))))

# --
# `ZBAQ_BATCH_SIZE` defines the number of elements that come into a manifest batch.
# This is used to workaround shell limit of argumnets, as we need to pass to zpaq the
# list of files as arguments.
ZBAQ_BATCH_SIZE?=10000

ZBAQ_INDEX_PATH:=$(ZBAQ_PATH)/index.zpaq
ZBAQ_CONTENT_PATH:=$(ZBAQ_PATH)/content-???.zpaq

EXCLUDES=
ifneq ($(wildcard $(ZBAQ_PATH)/meta.mk),)
include $(ZBAQ_PATH)/meta.mk
else
$(error ERR Can't find $(ZBAQ_PATH)/meta.mk)
endif



# FROM: <https://stackoverflow.com/questions/12340846/bash-shell-script-to-find-the-closest-parent-directory-of-several-files>
cmd-common-path=printf "%s\n%s\n" $1 | sed -e 'N;s/^\(.*\).*\n\1.*$$/\1/'  | sed 's/\(.*\)\/.*/\1/'

BACKUP_SOURCES:=$(shell echo $(foreach P,$(PATHS),$$(readlink -f $P)))
BACKUP_ROOT:=$(shell $(call cmd-common-path,$(BACKUP_SOURCES)))

ZPAQ=zpaq
FD=fd

manifest: $(ZBAQ_PATH)/manifest.lst
	@echo "Manifest: $<"
	echo "Batches: " $(ZBAQ_PATH)/manifest-*.lst

$(ZBAQ_PATH)/manifest.lst: .FORCE
	@echo $(BACKUP_SOURCES)
	# We create catalogue of all the files we need to manage using `fd`
	TEMP="$$(mktemp)"
	for SRC in $(BACKUP_SOURCES); do
		env -C "$(BACKUP_ROOT)" fd --full-path $$SRC >> "$$TEMP"
	done
	# We clean any previously created manifest file
	# FROM: <https://stackoverflow.com/questions/6363441/check-if-a-file-exists-with-a-wildcard-in-a-shell-script>
	if [ ! -z "$$(find "$(ZBAQ_PATH)" -maxdepth 1 -name 'manifest-*.lst' -printf 1 -quit)" ]; then
		rm $(ZBAQ_PATH)/manifest-*.lst
	fi
	truncate --size 0 "$@"
	# And now we split the TEMP file into chunks of ZBAQ_BATCH_SIZE lines.
	env -C $(ZBAQ_PATH) split -l$(ZBAQ_BATCH_SIZE) -d --additional-suffix .lst --verbose "$$TEMP"  manifest- | grep "'" | cut -d "'" -f2 >> $@
	# We cleanup the temp file
	unlink "$$TEMP"


all:
	@echo $(ZBAQ_PATH) $(BASE) $(PATHS)
	ROOT="$$($(call cmd-common-path,$(PATHS)))"
	if [ ! -d "$$ROOT" ]; then
		echo "ERR Could not find root directory: $$ROOT"
	fi
	echo env -C "$$ROOT" $(ZPAQ) add $(ZBAQ_CONTENT_PATH) -index $(ZBAQ_INDEX_PATH)

ZBAQ_CONTENT_PATH:=$(ZBAQ_PATH)/content-???.zpaq
backup:

.PHONY: all backup

.ONESHELL:
	@$()

.FORCE:

# EOF
