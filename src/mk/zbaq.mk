# --
# ## Make flags
.SHELLFLAGS=-ec
SPACE:=$(eval) $(eval)

# --
# We ensure that the `REQUIRES_BIN` list of tools is available on the system,
# otherwise we'll return an error.
REQUIRES_BIN=find readlink wc env truncate awk xargs
ifneq ($(REQUIRES_BIN),$(foreach T,$(REQUIRES_BIN),$(if $(shell which $T 2> /dev/null),$T,$(info ERR Missing tool $T))))
$(error FTL Some required tools are missing)
endif

ZBAQ_MAKEFILE=$(shell readlink -f $(lastword $(MAKEFILE_LIST)))
ZBAQ_PATH?=$(shell readlink -f $(dir $(lastword $(MAKEFILE_LIST))))
ZBAQ_NAME?=$(firstword $(subst .,$(SPACE),$(notdir $(ZBAQ_PATH))))

# --
# `ZBAQ_BATCH_SIZE` defines the number of elements that come into a manifest batch.
# This is used to workaround shell limit of arguments, as we need to pass to zpaq the
# list of files as arguments.
ZBAQ_BATCH_SIZE?=100000

# --
# `ZBAQ_INDEX_PATH` is where the index file is stored. The index is used to keep
# track of what is in the content, so that the content files can be moved/archived
# at will.
ZBAQ_INDEX_PATH?=$(ZBAQ_PATH)/index.zpaq
ZBAQ_CONTENT_PATH?=$(ZBAQ_PATH)/content-???.zpaq
ZBAQ_CONFIG_PATH?=$(ZBAQ_PATH)/config.mk
ZBAQ_MANIFEST_PATH?=$(ZBAQ_PATH)/manifest.lst

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
DEFAULT_IGNORED?=*.zbaq *.zpaq

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
cmd-make=make -f $$(realpath --relative-to=$$(pwd) $(ZBAQ_MAKEFILE)) $1

BACKUP_SOURCES:=$(shell echo $(foreach P,$(PATHS),$$(readlink -f $P)))
BACKUP_ROOT:=$(shell $(call cmd-common-path,$(BACKUP_SOURCES)))

REMOTE_PROTOCOL:=$(if $(findstring ://,$(REMOTE_URL)),$(firstword $(subst ://,$(SPACE),$(REMOTE_URL))),file)
REMOTE_PATH:=$(if $(findstring ://,$(REMOVE_ULR)),$(subst $(REMOTE_PROTOCOL)://,,$(REMOTE_URL)),$(REMOTE_URL))

# --
# `make info` displays overall information about the
info:
	@
	echo "ZPaq:     $(ZPAQ)"
	echo "Package:  $(ZBAQ_PATH)"
	echo "Root:     $(BACKUP_ROOT)"
	echo "Sources:  $(BACKUP_SOURCES)"
	echo "Ignored:  $(foreach P,$(IGNORED),$P)"
	if [ -e "$(ZBAQ_MANIFEST_PATH)" ]; then
		echo "Manifest: $(ZBAQ_MANIFEST_PATH) $$(wc -l "$(ZBAQ_MANIFEST_PATH)")"
	else
		echo "Manifest: ??? → run '$(call cmd-make,manifest)' to produce it"
	fi
	echo "Content:  $(ZBAQ_CONTENT_PATH) → $(wildcard $(ZBAQ_CONTENT_PATH))"


manifest: $(ZBAQ_MANIFEST_PATH)
	@cat $<

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
	BACKUP_TEMP=$$(mktemp -d)
	ERRORS=$$(mktemp)
	# We quote every file in the list so that it's shell-safe
	sed "s|'|\\\'|;s|^|'|;s|$$|'|" < "$<" > "$$BACKUP_TEMP/zpaq-args.lst"
	# We split the manifest in batches, which is used to work around the
	# limit of arguments.
	env -C "$$BACKUP_TEMP" split -d --lines=$(ZBAQ_BATCH_SIZE) --additional-suffix=.lst "zpaq-args.lst" zpaq-args-
	for CHUNK in $$BACKUP_TEMP/zpaq-args-*.lst; do
		echo "[backup/chunk] START processing chunk $$(basename $$CHUNK)"
		# This is a bit horrendous, but we need to create a script that passes
		# the list of files explicitly as arguments to `zpaq`, because it
		# doesn't support a list of files given by a file, and the options
		# like `-index` need to come after the files to include.
		echo -n 'env -C "$(BACKUP_ROOT)" $(ZPAQ) add '"'"'$(ZBAQ_CONTENT_PATH)'"'"' ' > "$$CHUNK.sh"
		tr '\n' ' ' < "$$CHUNK" >> "$$CHUNK.sh"
		echo -n '-index "$(ZBAQ_INDEX_PATH)"' >> "$$CHUNK.sh"
		chmod +x "$$CHUNK.sh"
		. "$$CHUNK.sh" 2>> "$$ERRORS"
		echo "[backup/chunk] END"
	done
	rm -rf "$$BACKUP_TEMP"
	echo "[backup/errors] START"
	cat "$$ERRORS"
	echo "[backup/errors] END"
	unlink "$$ERRORS"

list:
	@
	if [ ! -e "$(ZBAQ_INDEX_PATH)" ]; then
		echo "No backup currently existing → run '$(call cmd-make,backup)' to produce it"
	else
		$(ZPAQ) list "$(ZBAQ_INDEX_PATH)"
	fi

local:
	@du -hsc $(ZBAQ_PATH)/*

remote:
	@
	case "$(REMOTE_PROTOCOL)" in
		file)
			if [ ! -d "$(REMOTE_PATH)" ]; then
				echo "No remote path found '$(REMOTE_PATH)"
			else
				du -hsc $(REMOTE_PATH)/$(notdir $(ZBAQ_CONTENT_PATH))
			fi
			;;
		*)
			echo "ERR: Unsupported protocol $(REMOTE_PROTOCOL) in $(REMOTE_URL)"
			exit 1
			;;
	esac



flush:
	@
	case "$(REMOTE_PROTOCOL)" in
		file)
			if [ ! -d "$(REMOTE_PATH)" ]; then
				if ! mkdir -p "$(REMOTE_PATH)"; then
					echo "ERR: Could not create $(REMOTE_PATH) in $(REMOTE_URL)"
					exit 1
				fi
			fi
			;;
		*)
			echo "ERR: Unsupported protocol $(REMOTE_PROTOCOL) in $(REMOTE_URL)"
			exit 1
			;;
	esac

	for CONTENT in $(ZBAQ_CONTENT_PATH); do
		CONTENT_NAME=$$(basename "$$CONTENT")
		case "$(REMOTE_PROTOCOL)" in
			file)
				TARGET="$(REMOTE_PATH)/$$CONTENT_NAME"
				if [ -e "$$TARGET" ]; then
					echo "ERR: An archive already exists at "$$TARGET", aborting."
					exit 1
				else
					echo "flush: Moving $$CONTENT to $$TARGET"
					mv $$CONTENT $$TARGET
				fi
				;;
		esac
	done

# --
# ## Internal Functions

$(ZBAQ_MANIFEST_PATH): clean-manifest .FORCE
	@
	# We create catalogue of all the files we need to manage using `fd`
	truncate --size 0 "$@"
	for SRC in $(BACKUP_SOURCES); do
		env -C "$(BACKUP_ROOT)" find "$$SRC" '(' -type f -or -type l ')' $(FIND_IGNORED) -exec realpath --relative-base="$(BACKUP_ROOT)" '{}' ';' >> "$@"
	done

# --
# ## Make functions
#
.PHONY: info manifest list backup clean-manifest

print-%: .FORCE
	$(info $* =$(value $*))
	$(info $*:=$($*))

.ONESHELL:
	@$()

.FORCE:

# EOF
