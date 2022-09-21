# --
# # ZBaq Configuration Example

# The baseline configuration is to give the paths that you'd like to
# backup.
PATHS=\
	~/.ssh \
	~/Workspace/*--main

# You can define a REMOTE_URL
REMOTE_URL=file://$(USER)@nas.local:/data/backups/$(ZBAQ_NAME)

# EOF
