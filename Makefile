.PHONY: test test-iss test-xsim

test: test-iss

test-iss:
	uv run python -m unittest discover -s tests

test-xsim:
	./scripts/run-xsim.sh alu
