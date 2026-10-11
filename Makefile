#
# MIT License
#
# Copyright (c) 2025 Roberto Leinardi
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

# This repository is the source of the shared snippets, so it includes them
# straight from .mk/ instead of bootstrapping them like a consumer does.
REPO_ROOT := $(shell git rev-parse --show-toplevel)
include $(REPO_ROOT)/.mk/help.mk
include $(REPO_ROOT)/.mk/pre-commit.mk
include $(REPO_ROOT)/.mk/password.mk

.PHONY: test
test: ## Smoke-test every snippet; test the bootstrap script and the licence header check offline
	@"$(REPO_ROOT)/scripts/test-mk.sh"
	@"$(REPO_ROOT)/scripts/test-bootstrap.sh"
	@"$(REPO_ROOT)/scripts/test-license-headers.sh"
