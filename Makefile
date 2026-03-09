.PHONY: lint test test-integration test-all

lint:
	shellcheck -x macstate.sh lib/common.sh lib/diff.sh collectors/*.sh
	ruff check lib/ tests/
	ruff format --check lib/ tests/

test:
	bash tests/run_tests.sh
	python3 -m pytest tests/ -v

test-integration:
	bash tests/test_integration.sh

test-all: lint test test-integration
