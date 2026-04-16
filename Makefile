# mcp — test targets.
#
#   make test       Run the pytest suite for generate.py (config resolver).
#
# NOTE: 4 tests currently fail on main against HEAD of generate.py — pre-existing
# regressions (test_per_target_db_local, test_per_target_db_world4you,
# test_auth_db_shared, test_internal_keys_not_in_output). They need fixing in
# the tests or in generate.py — out of scope for CI bring-up.

PYTEST ?= pytest

.PHONY: test

test:
	$(PYTEST) tests/ -v
