# --
# ## Make flags
.SHELLFLAGS=-ec

# --
# We ensure that the `REQUIRES_BIN` list of tools is available on the system,
# otherwise we'll return an error.
REQUIRES_BIN=find readlink wc env truncate awk xargs
ifneq ($(REQUIRES_BIN),$(foreach T,$(REQUIRES_BIN),$(if $(shell which $T 2> /dev/null),$T,$(info ERR Missing tool $T))))
$(error FTL Some required tools are missing)
endif


ZBAQ_MAKEFILE=$(shell readlink -f $(lastword $(MAKEFILE_LIST)))
ZBAQ_PATH?=$(shell readlink -f $(dir $(lastword $(MAKEFILE_LIST))))

# --
# `ZBAQ_BATCH_SIZE` defines the number of elements that come into a manifest batch.
# This is used to workaround shell limit of arguments, as we need to pass to zpaq the
# list of files as arguments.
ZBAQ_BATCH_SIZE?=10000

# --
# `ZBAQ_INDEX_PATH` is where the index file is stored. The index is used to keep
# track of what is in the content, so that the content files can be moved/archived
# at will.
ZBAQ_INDEX_PATH?=$(ZBAQ_PATH)/index.zpaq
ZBAQ_CONTENT_PATH?=$(ZBAQ_PATH)/content-???.zpaq
ZBAQ_CONFIG_PATH?=$(ZBAQ_PATH)/config.mk

# --
# ## Ignored files
#
# You probably don't want to backup everything, and the `DEFAULT_IGNORED`
# list of globs will make sure the directories or files matching these
# are going to e skipped.
GITIGNORE_PATH?=$(HOME)/.gitignore
GITIGNORE_PATTERNS?=$(filter %,$(filter-out #%,$(file <$(GITIGNORE_PATH))))

# --
# The `DEFAULT_IGNORED` are patterns that are ignored by default, which can
# be overriden in the config.
DEFAULT_IGNORED?=.deps/run

# --
# The `IGNORED` variable contains the list of all ignored patterns. This will
# be used to define the arguments to
IGNORED+=$(foreach P,$(GITIGNORE_PATTERNS) $(DEFAULT_IGNORED),$P)

# --
# We make sure that `zpaq` is available
ifeq ($(ZPAQ),)
ZPAQ:=$(shell which zpaq 2> /dev/null)
ifeq ($(ZPAQ),)
$(error ERR Can't find 'zpaq' command, install it or set the ZPAQ variable)
endif
else
ifeq ($(shell which zpaq 2> /dev/null),)
$(error ERR Can't find zpaq at '$(ZPAQ)' install it or set the ZPAQ variable)
endif
endif

# --
#  The `config.mk` file is where the configu

ifneq ($(wildcard $(ZBAQ_CONFIG_PATH)),)
include $(ZBAQ_PATH)/config.mk
else
$(error ERR Can't find $(ZBAQ_CONFIG_PATH))
endif

# --
# We convert ignored patterns into `find` arguments
FIND_IGNORED:=$(foreach P,$(IGNORED),-a -not -path '*/$P/*')

# FROM: <https://stackoverflow.com/questions/12340846/bash-shell-script-to-find-the-closest-parent-directory-of-several-files>
cmd-common-path=printf "%s\n%s\n" $1 | sed -e 'N;s/^\(.*\).*\n\1.*$$/\1/'  | sed 's/\(.*\)\/.*/\1/'

BACKUP_SOURCES:=$(shell echo $(foreach P,$(PATHS),$$(readlink -f $P)))
BACKUP_ROOT:=$(shell $(call cmd-common-path,$(BACKUP_SOURCES)))


# --
# `make info` displays overall information about the
info:
	@
	echo "ZPaq:     $(ZPAQ)"
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
	@find "$(ZBAQ_PATH)" -maxdepth 1 -name 'manifest-*.lst' -exec cat {} ';'

clean-manifest: .FORCE
	@
	# We clean any previously created manifest file
	# FROM: <https://stackoverflow.com/questions/6363441/check-if-a-file-exists-with-a-wildcard-in-a-shell-script>
	if [ ! -z "$$(find "$(ZBAQ_PATH)" -maxdepth 1 -name 'manifest-*.lst' -printf 1 -quit)" ]; then
		rm $(ZBAQ_PATH)/manifest-*.lst
	fi

backup: $(ZBAQ_PATH)/manifest.lst
	@
	if [ ! -d "$(BACKUP_ROOT)" ]; then
		echo "ERR Could not find root directory: $(BACKUP_ROOT)"
	fi
	TEMP=$$(mktemp)
	for MANIFEST in $$(cat $<); do
		echo $$(MANIFEST)
		# cp $(ZBAQ_PATH)/$$MANIFEST $$TEMP
		# echo "-index $(ZBAQ_INDEX_PATH)" >> $$TEMP
		# cat $$TEMP |  xargs env -C $(BACKUP_ROOT) $(ZPAQ) add $(ZBAQ_CONTENT_PATH)
	done
	unlink "$$TEMP"

# --
# ## Internal Functions

$(ZBAQ_PATH)/manifest.lst: clean-manifest .FORCE
	@
	# We create catalogue of all the files we need to manage using `fd`
	TEMP="$$(mktemp)"
	for SRC in $(BACKUP_SOURCES); do
		env -C "$(BACKUP_ROOT)" find "$$SRC" '(' -type f -or -type l ')' $(FIND_IGNORED) >> "$$TEMP"
	done
	truncate --size 0 "$@"
	# And now we split the TEMP file into chunks of ZBAQ_BATCH_SIZE lines.
	env -C $(ZBAQ_PATH) split -l$(ZBAQ_BATCH_SIZE) -d --additional-suffix .lst --verbose "$$TEMP"  manifest- | grep "'" | cut -d "'" -f2 >> $@
	# We cleanup the temp file
	unlink "$$TEMP"



# --
# ## Make functions
#
.PHONY: info manifest clean-manifest

print-%: .FORCE
	$(info $* =$(value $*))
	$(info $*:=$($*))

.ONESHELL:
	@$()

.FORCE:

# EOF
