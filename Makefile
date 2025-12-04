REPO_ROOT := $(shell git rev-parse --show-toplevel)
include $(REPO_ROOT)/.mk/help.mk
include $(REPO_ROOT)/.mk/pre-commit.mk
include $(REPO_ROOT)/.mk/password.mk
