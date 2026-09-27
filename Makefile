# Tally developer entry points.
# TallyCore builds and tests on Linux in a pinned Swift toolchain container
# (the same digest as CI's core-linux job). iOS builds run on macOS CI.

SWIFT_IMAGE ?= docker.io/library/swift@sha256:3fd7537e088df14007e5c9dd71a1b4d91b19067df727b17294ae0f6ea79f6423 # 6.4.0-noble
CONTAINER   ?= podman
CORE_DIR    := $(CURDIR)/packages/TallyCore
RUN_CORE     = $(CONTAINER) run --rm --network none -v $(CORE_DIR):/pkg:Z -w /pkg $(SWIFT_IMAGE)

.PHONY: core-test core-build core-deps placeholders

core-deps: ## Fetch pinned SwiftPM dependencies (needs network; tests then run offline)
	$(CONTAINER) run --rm -v $(CORE_DIR):/pkg:Z -w /pkg $(SWIFT_IMAGE) swift package resolve

core-test: core-deps ## Build and run every TallyCore test on Linux (no network)
	$(RUN_CORE) bash -c 'swift --version && swift test'

core-build: core-deps ## Compile TallyCore with warnings treated as errors
	$(RUN_CORE) swift build -Xswiftc -warnings-as-errors

placeholders: ## List go-live placeholders still in code (GO-LIVE GL-02)
	scripts/go-live/find-placeholders.sh
