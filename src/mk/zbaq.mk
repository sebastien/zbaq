.SHELLFLAGS = -ec

ZBAQ_MAKEFILE=$(shell readlink -f $(lastword $(MAKEFILE_LIST)))
ZBAQ_PATH?=$(shell readlink -f $(dir $(lastword $(MAKEFILE_LIST))))

# --
# `ZBAQ_BATCH_SIZE` defines the number of elements that come into a manifest batch.
# This is used to workaround shell limit of arguments, as we need to pass to zpaq the
# list of files as arguments.
ZBAQ_BATCH_SIZE?=10000

ZBAQ_INDEX_PATH:=$(ZBAQ_PATH)/index.zpaq
ZBAQ_CONTENT_PATH:=$(ZBAQ_PATH)/content-???.zpaq

GITIGNORE_PATH?=$(HOME)/.gitignore
DEFAULT_IGNORED?=.deps/run
GIT_IGNORED?=$(file <$(GITIGNORE_PATH))
IGNORED+=$(foreach P,$(GIT_IGNORED) $(DEFAULT_IGNORED),$P)

ifneq ($(wildcard $(ZBAQ_PATH)/config.mk),)
include $(ZBAQ_PATH)/config.mk
else
$(error ERR Can't find $(ZBAQ_PATH)/config.mk)
endif

FIND_IGNORED:=$(foreach P,$(IGNORED),$(if $(findstring /,$P),-a -not -path '$P' -a -not -path '*/$P/*',-a -not -name '$P'))

# FROM: <https://stackoverflow.com/questions/12340846/bash-shell-script-to-find-the-closest-parent-directory-of-several-files>
cmd-common-path=printf "%s\n%s\n" $1 | sed -e 'N;s/^\(.*\).*\n\1.*$$/\1/'  | sed 's/\(.*\)\/.*/\1/'

BACKUP_SOURCES:=$(shell echo $(foreach P,$(PATHS),$$(readlink -f $P)))
BACKUP_ROOT:=$(shell $(call cmd-common-path,$(BACKUP_SOURCES)))

ZPAQ=zpaq
FD=fd

# --
# `make info` displays overall information about the
info:
	@
	echo "Package:  $(ZBAQ_PATH)"
	echo "Root:     $(BACKUP_ROOT)"
	echo "Sources:  $(BACKUP_SOURCES)"
	echo "Ignored:  $(foreach P,$(IGNORED),$P)"
	if [ ! -z "$$(find "$(ZBAQ_PATH)" -maxdepth 1 -name 'manifest-*.lst' -printf 1 -quit)" ]; then
		echo "Manifest: $(ZBAQ_PATH)/manifest.lst"
		echo "Batches: " $(ZBAQ_PATH)/manifest-*.lst
		echo "Files:    $$(wc -l $(ZBAQ_PATH)/manifest-*.lst | tail -n1 | awk '{print $$1}')"
	else
		echo "Manifest: ??? → run 'make -f $$(realpath --relative-to=$$(pwd) $(ZBAQ_MAKEFILE)) manifest' to produce it"
	fi


manifest: $(ZBAQ_PATH)/manifest.lst
	@echo find "$(ZBAQ_PATH)" -maxdepth 1 -name 'manifest-*.lst' -exec cat {} ';'

clean-manifest: .FORCE
	@
	# We clean any previously created manifest file
	# FROM: <https://stackoverflow.com/questions/6363441/check-if-a-file-exists-with-a-wildcard-in-a-shell-script>
	if [ ! -z "$$(find "$(ZBAQ_PATH)" -maxdepth 1 -name 'manifest-*.lst' -printf 1 -quit)" ]; then
		rm $(ZBAQ_PATH)/manifest-*.lst
	fi

$(ZBAQ_PATH)/manifest.lst: clean-manifest .FORCE
	echo $(BACKUP_SOURCES)
	# We create catalogue of all the files we need to manage using `fd`
	TEMP="$$(mktemp)"
	for SRC in $(BACKUP_SOURCES); do
		echo env -C "$(BACKUP_ROOT)" find "$$SRC" -type f -or -type d $(FIND_IGNORED) >> "$$TEMP"
		env -C "$(BACKUP_ROOT)" find "$$SRC" -type f -or -type d $(FIND_IGNORED) >> "$$TEMP"
	done
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

.PHONY: all backup clean-manifest

print-%: .FORCE
	$(info $* =$(value $*))
	$(info $*:=$($*))

.ONESHELL:
	@$()

.FORCE:

# EOF
