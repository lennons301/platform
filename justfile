# Command runner for the platform repo. `just --list` for the menu.

# Install the pinned tools (shellcheck, yq, jq)
setup:
    mise install

# Run the estate conformity report against locally cloned repos
dev *ARGS:
    ./checks/check-estate.sh {{ARGS}}

# shellcheck over checks/ and scripts/
lint:
    ./scripts/lint.sh

# Shell test suite for the check tooling
test:
    ./checks/tests/run-tests.sh
