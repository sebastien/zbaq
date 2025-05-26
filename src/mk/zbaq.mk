#  --
#  ```
#  ______     ______     ______     ______
# /\___  \   /\  == \   /\  __ \   /\  __ \
# \/_/  /__  \ \  __<   \ \  __ \  \ \ \/\_\
#   /\_____\  \ \_____\  \ \_\ \_\  \ \___\_\
#   \/_____/   \/_____/   \/_/\/_/   \/___/_/
#
# ```
#
# ZBaq is a backup system based on `make` and using `zpaq` as the archival
# format.


# --
# ## Configuration

# --
# `BACKUP_ROOT` defines the common root of all paths. It's optional, and will
# remove the root from all backed up paths;
BACKUP_ROOT?=
# --
# `BACKUP_PATHS` defines the list of paths to be backed up.
BACKUP_PATHS?=
# --
# `BACKUP_EXCLUDE` defines the list of glob patterns for files and dir
# basnames to be excluded.
BACKUP_EXCLUDE?=
# --
# `BACKUP_STATE` defines where the backup state is stored.
BACKUP_STATE?=
# --
# `BACKUP_DESTINATION` defines where the backup is to be stored (as a
# destination).
BACKUP_DESTINATION?=

# =============================================================================
# COLORS
# =============================================================================

# We respect https://no-color.org/
NO_COLOR?=
NO_INTERACTIVE?=
TERM?=
YELLOW        ?=
ORANGE        ?=
GREEN         ?=
GOLD          ?=
GOLD_DK       ?=
BLUE_DK       ?=
BLUE          ?=
BLUE_LT       ?=
CYAN          ?=
RED           ?=
PURPLE_DK     ?=
PURPLE        ?=
PURPLE_LT     ?=
GRAY          ?=
GRAYLT        ?=
REGULAR       ?=
RESET         ?=
BOLD          ?=
UNDERLINE     ?=
REV           ?=
DIM           ?=
ifneq (,$(shell which tput 2> /dev/null))
ifeq (,$(NO_COLOR))
TERM?=xterm-color
BLUE_DK       :=$(shell TERM="$(TERM)" echo $$(tput setaf 27))
BLUE          :=$(shell TERM="$(TERM)" echo $$(tput setaf 33))
BLUE_LT       :=$(shell TERM="$(TERM)" echo $$(tput setaf 117))
YELLOW        :=$(shell TERM="$(TERM)" echo $$(tput setaf 226))
ORANGE        :=$(shell TERM="$(TERM)" echo $$(tput setaf 208))
GREEN         :=$(shell TERM="$(TERM)" echo $$(tput setaf 118))
GOLD          :=$(shell TERM="$(TERM)" echo $$(tput setaf 214))
GOLD_DK       :=$(shell TERM="$(TERM)" echo $$(tput setaf 208))
CYAN          :=$(shell TERM="$(TERM)" echo $$(tput setaf 51))
RED           :=$(shell TERM="$(TERM)" echo $$(tput setaf 196))
PURPLE_DK     :=$(shell TERM="$(TERM)" echo $$(tput setaf 55))
PURPLE        :=$(shell TERM="$(TERM)" echo $$(tput setaf 92))
PURPLE_LT     :=$(shell TERM="$(TERM)" echo $$(tput setaf 163))
GRAY          :=$(shell TERM="$(TERM)" echo $$(tput setaf 153))
GRAYLT        :=$(shell TERM="$(TERM)" echo $$(tput setaf 231))
REGULAR       :=$(shell TERM="$(TERM)" echo $$(tput setaf 7))
RESET         :=$(shell TERM="$(TERM)" echo $$(tput sgr0))
BOLD          :=$(shell TERM="$(TERM)" echo $$(tput bold))
UNDERLINE     :=$(shell TERM="$(TERM)" echo $$(tput smul))
REV           :=$(shell TERM="$(TERM)" echo $$(tput rev))
DIM           :=$(shell TERM="$(TERM)" echo $$(tput dim))
endif
endif

# =============================================================================
# MAKEFILE CONFIG
# =============================================================================

1?=
2?=
3?=
4?=
5?=
6?=
7?=
COMMA:=,
BOLD=
NULL:=
SPACE:=$(NULL) $(NULL)
define EOL
$(if 1,
,)
endef

SHELL:=bash
.SHELLFLAGS:=-euo pipefail -c
MAKEFLAGS+=--warn-undefined-variables
MAKEFLAGS+=--no-builtin-rules

fmt_input =$(if $($1),$(CYAN)$($1),$(RED)$1 missing)$(RESET)
fmt_var   =$(if $($1),$(BLUE)$($1),$(RED)$1 missing)$(RESET)
fmt_output=$(if $($1),$(GREEN)$($1),$(RED)$1 missing)$(RESET)
fmt_path  =$(CYAN)$1$(RESET)
fmt_error =$(RED)!!! $1$(RESET)
fmt_tip   =$(SPACE)👉   $1$(RESET)
fmt_rule  = ┄―→ $(CYAN)$@: $(BLUE)$1$(RESET)
fmt_action= ┄┄┄ $(CYAN)|$(RESET) $1$(RESET)
fmt_result=$(GREEN)←―― $(CYAN)|$(RESET) $1$(RESET)

# --
# We ensure that the `REQUIRES_BIN` list of tools is available on the system,
# otherwise we'll return an error.
REQUIRES_BIN=find readlink wc env truncate awk xargs
ifneq ($(REQUIRES_BIN),$(foreach T,$(REQUIRES_BIN),$(if $(shell which $T 2> /dev/null),$T,$(info ERR Missing tool $T))))
$(error FTL Some required tools are missing)
endif

ZBAQ_MAKEFILE=$(shell readlink -f $(lastword $(MAKEFILE_LIST)))
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
ZBAQ_MANIFEST_PATH?=$(ZBAQ_PATH)/manifest.lst

# --
# ## Ignored files
#
# You probably don't want to backup everything, and the `DEFAULT_EXCLUDE`
# list of globs will make sure the directories or files matching these
# are going to e skipped.
GITIGNORE_PATH?=$(HOME)/.gitignore
GITIGNORE_PATTERNS?=$(filter %,$(filter-out #%,$(file <$(GITIGNORE_PATH))))

# --
# The `DEFAULT_EXCLUDE` are patterns that are ignored by default, which can
# be overriden in the config.
DEFAULT_EXCLUDE?=*.zbaq *.zpaq node_modules build dist cache

TMPDIR?=$(if $(HOME),$(HOME),/tmp)

# --
# The `EXCLUDE` variable contains the list of all ignored patterns. This will
# be used to define the arguments to
BACKUP_EXCLUDE+=$(foreach P,$(GITIGNORE_PATTERNS) $(DEFAULT_EXCLUDE),$P)

ZPAQ?=
# --
# We make sure that `zpaq` is available
ifeq ($(ZPAQ),)
ZPAQ:=$(shell which zpaq 2> /dev/null)
ifeq ($(ZPAQ),)
$(error $(RED)ERR Can't find 'zpaq' command, install it or set the ZPAQ variable$(RESET))
endif
else
ifeq ($(shell which zpaq 2> /dev/null),)
$(error $(RED)ERR Can't find zpaq at '$(ZPAQ)' install it or set the ZPAQ variable$(RESET))
endif
endif


# --
#  The `config.mk` file is where the confiuration is

# Otherwise it will be the parent directory of the makefile
ZBAQ_PATH?=$(shell readlink -f $(dir $(firstword $(MAKEFILE_LIST))))/zbaq

ifeq ($(BACKUP_PATHS),)
$(error ERR BACKUP_PATHS variable is empty)
endif

# --
# We convert ignored patterns into `find` arguments
FIND_EXCLUDE:=$(foreach P,$(BACKUP_EXCLUDE),-a -not -path '*/$P/*')

# FROM: <https://stackoverflow.com/questions/12340846/bash-shell-script-to-find-the-closest-parent-directory-of-several-files>
cmd-common-path=printf "%s\n%s\n" $1 | sed -e 'N;s/^\(.*\).*\n\1.*$$/\1/'  | sed 's/\(.*\)\/.*/\1/'
cmd-make=make -f $$(realpath --relative-to=$$(pwd) $(ZBAQ_MAKEFILE)) $1

BACKUP_SOURCES:=$(shell echo $(foreach P,$(BACKUP_PATHS),$$(readlink -f $P)))
BACKUP_ROOT:=$(if $(filter 1,$(words $(BACKUP_SOURCES))),$(BACKUP_SOURCES),$(shell $(call cmd-common-path,$(BACKUP_SOURCES))))
ifeq ($(BACKUP_ROOT),)
	$(error ERR !!! Missing BACKUP_SOURCES in config.mk)
endif

BACKUP_DESTINATION_PROTOCOL:=$(if $(findstring ://,$(BACKUP_DESTINATION)),$(firstword $(subst ://,$(SPACE),$(BACKUP_DESTINATION))),file)
BACKUP_DESTINATION_PATH:=$(if $(findstring ://,$(BACKUP_DESTINATION)),$(subst $(BACKUP_DESTINATION_PROTOCOL)://,,$(BACKUP_DESTINATION)),$(BACKUP_DESTINATION))

.PHONY: help
help:
	@
	cat <<EOF
	|    ______     ______     ______     ______
	|   /\___  \   /\  == \   /\  __ \   /\  __ \\
	|   \/_/  /__  \ \  __<   \ \  __ \  \ \ \/\_\\
	|     /\_____\  \ \_____\  \ \_\ \_\  \ \___\_\\
	|     \/_____/   \/_____/   \/_/\/_/   \/___/_/
	|
	| Zbaq is an incremental local or remote backup tool that uses 'zpaq' and 'make'
	| to easily and seamlessly backup your data
	|
	| Backing up '$(BACKUP_SOURCES)' to '$(BACKUP_DESTINATION)'
	|
	| Basic operations:
	| - zbaq backup:   Backups new files
	| - zbaq list:     List previous backups
	| - zbaq edit:     Opens $$EDITOR to edit the config
	|
	| Checking status:
	| - zbaq info:     Show information about the config
	| - zbaq manifest: Shows what has been backed up
	| - zbaq list:     List previous backups
	|
	| Managing local/remote storage
	| - zbaq local:    List locally stored backups
	| - zbaq remote:   List remotely stored backups
	| - zbaq flush:    Moves local backups to the remote store
	|
	| Configuration:
	| - BACKUP_ROOT=$(call fmt_input,BACKUP_ROOT)
	| - BACKUP_PATHS=$(call fmt_input,BACKUP_PATHS)
	| - BACKUP_DESTINATION=$(call fmt_input,BACKUP_DESTINATION)
	| - BACKUP_EXCLUDED=$(call fmt_input,BACKUP_EXCLUDE)
	|
	| Zbaq:
	| - ZBAQ_PATH=$(call fmt_var,ZBAQ_PATH)
	| - ZBAQ_MANIFEST_PATH=$(call fmt_var,ZBAQ_MANIFEST_PATH,run '$(call cmd-make,manifest)')
	EOF

# --
# `make info` displays overall information about the
.PHONY: info
info:
	@
	cat <<EOF
	» ZBaq Information
	|
	» Configuration:
	| - $(BOLD)BACKUP_ROOT$(RESET):        $(call fmt_input,BACKUP_ROOT)
	| - $(BOLD)BACKUP_PATHS$(RESET):       $(call fmt_input,BACKUP_PATHS)
	| - $(BOLD)BACKUP_DESTINATION$(RESET): $(call fmt_input,BACKUP_DESTINATION)
	| - $(BOLD)BACKUP_SOURCES$(RESET):     $(call fmt_input,BACKUP_SOURCES)
	| - $(BOLD)BACKUP_EXCLUDE$(RESET):     $(call fmt_input,BACKUP_EXCLUDE)
	|
	» Backup Working Directory:
	| - $(BOLD)ZPAQ$(RESET):               $(call fmt_var,ZPAQ)
	| - $(BOLD)ZBAQ_PATH$(RESET):          $(call fmt_var,ZBAQ_PATH)
	| - $(BOLD)ZBAQ_MANIFEST_PATH$(RESET): $(call fmt_var,ZBAQ_MANIFEST_PATH,run '$(call cmd-make,manifest)')
	EOF

# FIXME: Not sure this still stands
.PHONY: edit
edit:
	@echo "$(call fmt_rule,Editing using $(call fmt_var,EDITOR) at $(call fmt_var,ZBAQ_PATH))"
	env -C "$(ZBAQ_PATH)" $(if $(EDITOR),$(EDITOR),vi) $(realpath $(ZBAQ_PATH)/Makefile)

.PHONY: manifest
manifest: $(ZBAQ_MANIFEST_PATH)
	@echo "$(call fmt_rule,Manifest at: $(call fmt_path,$(ZBAQ_MANIFEST_PATH)))"
	cat "$<"
	echo "$(call fmt_result,$$(wc -l "$<" | cut -d' ' -f1) lines)"

.PHONY: clean-manifest
clean-manifest: .FORCE
	@echo "$(call fmt_rule,Cleaning up manifest files in $(call fmt_var,ZBAQ_PATH))"
	if [ -e "$(ZBAQ_PATH)" ]; then
		find "$(ZBAQ_PATH)" -name 'manifest-*.lst' -exec unlink {} ';'
	fi

.PHONY: backup
backup: $(ZBAQ_PATH)/manifest.lst
	@echo "$(call fmt_rule,Running backup using manifest: $(GREEN)$<)"
	if [ ! -d "$(BACKUP_ROOT)" ]; then
		echo "ERR Could not find root directory: $(BACKUP_ROOT)"
	fi
	BACKUP_TEMP=$$(mktemp -p "$(TMPDIR)" -d zbaq-backup-XXX )
	if [ ! -e "$$BACKUP_TEMP" ]; then
		mkdir -p "$$BACKUP_TEMP"
	fi
	ERRORS=$${BACKUP_TEMP}.log
	if [ ! -e "$$BACKUP_TEMP" ]; then
		echo "ERR Could not got to temp directory: $$BACKUP_TEMP"
		exit 1
	fi
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

.PHONY: list
list:
	@echo "$(call fmt_rule,Listing the backed up files: $(call fmt_var,ZBAQ_INDEX_PATH))"
	if [ ! -e "$(ZBAQ_INDEX_PATH)" ]; then
		echo "No backup currently existing → run '$(call cmd-make,backup)' to produce it"
	else
		$(ZPAQ) list "$(ZBAQ_INDEX_PATH)"
	fi

.PHONY: local
local:
	@echo "$(call fmt_rule,Local size of backup index: $(call fmt_var,ZBAQ_PATH))"
	du -hsc $(ZBAQ_PATH)/*


.PHONY: remote
remote: check-remote
	@
	case "$(BACKUP_DESTINATION_PROTOCOL)" in
		file)
			if [ -z "$$(ls $(BACKUP_DESTINATION_PATH)/$(notdir $(ZBAQ_CONTENT_PATH)) 2> /dev/null)" ]; then
				echo "No archive found at remote path: '$(BACKUP_DESTINATION_PATH)'"
			else
				du -hsc "$(BACKUP_DESTINATION_PATH)/$(notdir $(ZBAQ_CONTENT_PATH))"
			fi
		;;
		*)
		;;
	esac

.PHONY: check-remote
check-remote:
	@
	case "$(BACKUP_DESTINATION_PROTOCOL)" in
		file)
			if [ ! -d "$(BACKUP_DESTINATION_PATH)" ]; then
				echo "No remote path found $(BACKUP_DESTINATION_PATH)"
				exit 1
			fi
			;;
		*)
			echo "ERR: Unsupported protocol $(BACKUP_DESTINATION_PROTOCOL) in $(BACKUP_DESTINATION_URL)"
			exit 1
			;;
	esac


.PHONY: flush
flush: check-remote
	@
	case "$(BACKUP_DESTINATION_PROTOCOL)" in
		file)
			if [ ! -d "$(BACKUP_DESTINATION_PATH)" ]; then
				if ! mkdir -p "$(BACKUP_DESTINATION_PATH)"; then
					echo "ERR: Could not create $(BACKUP_DESTINATION_PATH) in $(BACKUP_DESTINATION_URL)"
					exit 1
				fi
			fi
			;;
		*)
			echo "ERR: Unsupported protocol $(BACKUP_DESTINATION_PROTOCOL) in $(BACKUP_DESTINATION_URL)"
			exit 1
			;;
	esac

	for CONTENT in $(ZBAQ_CONTENT_PATH); do
		CONTENT_NAME=$$(basename "$$CONTENT")
		case "$(BACKUP_DESTINATION_PROTOCOL)" in
			file)
				TARGET="$(BACKUP_DESTINATION_PATH)/$$CONTENT_NAME"
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
	@echo "$(call fmt_result,Updating the manifest file)"
	mkdir -p "$(dir $@)"
	# We create catalogue of all the files we need to manage using `fd`
	truncate --size 0 "$@"

	if [ ! -e "$(BACKUP_ROOT)" ]; then
		echo "ERR !!! Backup root does not exist: '$(BACKUP_ROOT)'"
		exit 1
	fi
	for SRC in $(BACKUP_SOURCES); do
		if [ ! -e "$$SRC" ]; then
			echo "WRN -!- Source does not exist: $(call fmt_path,$$SRC)"
		else
			echo "$(call fmt_action,Adding files in $(call fmt_path,$$SRC) to manifest…)"
			env -C "$(BACKUP_ROOT)" find "$$SRC" '(' -type f -or -type l ')' $(FIND_EXCLUDE) -exec realpath --relative-base="$(BACKUP_ROOT)" '{}' ';' >> "$@"
			echo "$(call fmt_action,→ $$(wc -l "$@" | cut -d' ' -f1) lines)"
		fi
	done
	echo "$(call fmt_result,$$(wc -l "$@" | cut -d' ' -f1) lines)"

# --
# ## Make functions
#
.PHONY: info manifest list backup clean-manifest

print-%: .FORCE
	$(info $* =$(value $*))
	$(info $*:=$($*))

.ONESHELL:
	@

.FORCE:

# EOF
