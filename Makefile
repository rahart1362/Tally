# Tally developer entry points.
# TallyCore builds and tests on Linux in a pinned Swift toolchain container
# (the same digest as CI's core-linux job). iOS builds run on macOS CI.

SWIFT_IMAGE ?= docker.io/library/swift@sha256:3fd7537e088df14007e5c9dd71a1b4d91b19067df727b17294ae0f6ea79f6423 # 6.4.0-noble
CONTAINER   ?= podman
CORE_DIR    := $(CURDIR)/packages/TallyCore
# The whole repo is mounted so tests can read fixtures/canvas; only .build is written.
RUN_CORE     = $(CONTAINER) run --rm --network none -v $(CURDIR):/repo:Z -w /repo/packages/TallyCore $(SWIFT_IMAGE)

.PHONY: core-test core-build core-deps placeholders

core-deps: ## Fetch pinned SwiftPM dependencies (needs network; tests then run offline)
	$(CONTAINER) run --rm -v $(CURDIR):/repo:Z -w /repo/packages/TallyCore $(SWIFT_IMAGE) swift package resolve

core-test: core-deps ## Build and run every TallyCore test on Linux (no network)
	$(RUN_CORE) bash -c 'swift --version && swift test'

core-build: core-deps ## Compile TallyCore and its tests with warnings treated as errors
	$(RUN_CORE) swift build --build-tests -Xswiftc -warnings-as-errors

# CS-04 (crash-safety.md): sanitizer lanes. Each uses its own --scratch-path so it never touches
# the normal .build cache core-build/core-test use, and each needs its own `swift package
# resolve` first (a new scratch path needs its own checkouts before it can build --network none).
#
# ThreadSanitizer needs ASLR disabled on this host's kernel (`setarch $$(uname -m) -R`); without
# it, TSan aborts with "encountered an incompatible memory layout but was unable to disable
# ASLR". `setarch` itself calls `personality()`, which Podman/runc's default seccomp profile
# blocks (reproduced: fails with "Function not implemented" under the default profile) — hence
# --security-opt seccomp=unconfined, scoped to only these two targets and only this ephemeral,
# --network none, --rm container; core-build/core-test/core-deps are unaffected.
TSAN_SCRATCH := /repo/packages/TallyCore/.build-tsan
ASAN_SCRATCH := /repo/packages/TallyCore/.build-asan
RUN_SANITIZED = $(CONTAINER) run --rm --network none --security-opt seccomp=unconfined -v $(CURDIR):/repo:Z -w /repo/packages/TallyCore $(SWIFT_IMAGE)

.PHONY: core-tsan core-asan core-tsan-deps core-asan-deps

core-tsan-deps:
	$(CONTAINER) run --rm -v $(CURDIR):/repo:Z -w /repo/packages/TallyCore $(SWIFT_IMAGE) swift package resolve --scratch-path $(TSAN_SCRATCH)

core-asan-deps:
	$(CONTAINER) run --rm -v $(CURDIR):/repo:Z -w /repo/packages/TallyCore $(SWIFT_IMAGE) swift package resolve --scratch-path $(ASAN_SCRATCH)

core-tsan: core-tsan-deps ## Run every TallyCore test under ThreadSanitizer
	$(RUN_SANITIZED) bash -c 'setarch $$(uname -m) -R swift test --sanitize=thread --scratch-path $(TSAN_SCRATCH)'

core-asan: core-asan-deps ## Run every TallyCore test under AddressSanitizer + LeakSanitizer
	$(CONTAINER) run --rm --network none --security-opt seccomp=unconfined \
		-e LSAN_OPTIONS=suppressions=/repo/packages/TallyCore/lsan-suppressions.txt \
		-v $(CURDIR):/repo:Z -w /repo/packages/TallyCore $(SWIFT_IMAGE) \
		bash -c 'setarch $$(uname -m) -R swift test --sanitize=address --scratch-path $(ASAN_SCRATCH)'

placeholders: ## List go-live placeholders still in code (GO-LIVE GL-02)
	scripts/go-live/find-placeholders.sh
