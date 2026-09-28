# Tally developer entry points.
# TallyCore builds and tests on Linux in a pinned Swift toolchain container
# (the same digest as CI's core-linux job). iOS builds run on macOS CI.

SWIFT_IMAGE ?= docker.io/library/swift@sha256:3fd7537e088df14007e5c9dd71a1b4d91b19067df727b17294ae0f6ea79f6423 # 6.4.0-noble
CONTAINER   ?= podman
CORE_DIR    := $(CURDIR)/packages/TallyCore
# The whole repo is mounted so tests can read fixtures/canvas; only .build is written.
RUN_CORE     = $(CONTAINER) run --rm --network none -v $(CURDIR):/repo:Z -w /repo/packages/TallyCore $(SWIFT_IMAGE)

.PHONY: core-test core-build core-deps core-perf placeholders

core-deps: ## Fetch pinned SwiftPM dependencies (needs network; tests then run offline)
	$(CONTAINER) run --rm -v $(CURDIR):/repo:Z -w /repo/packages/TallyCore $(SWIFT_IMAGE) swift package resolve

core-test: core-deps ## Build and run every TallyCore test on Linux (no network)
	$(RUN_CORE) bash -c 'swift --version && swift test'

core-build: core-deps ## Compile TallyCore and its tests with warnings treated as errors
	$(RUN_CORE) swift build --build-tests -Xswiftc -warnings-as-errors

core-perf: core-deps ## PERF-01: run TallyPerfTests in release mode (real numbers; skipped entirely by core-test)
	$(RUN_CORE) swift test -c release --filter TallyPerfTests

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
# Sanitized builds run 5-15x slower, so the tests' hang-detector budgets are scaled up
# (TallyTestSupport/TestTimeBudget.swift).
SANITIZER_TIME_SCALE ?= 10
RUN_SANITIZED = $(CONTAINER) run --rm --network none --security-opt seccomp=unconfined -e TALLY_TEST_TIME_SCALE=$(SANITIZER_TIME_SCALE) -v $(CURDIR):/repo:Z -w /repo/packages/TallyCore $(SWIFT_IMAGE)

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
		-e TALLY_TEST_TIME_SCALE=$(SANITIZER_TIME_SCALE) \
		-v $(CURDIR):/repo:Z -w /repo/packages/TallyCore $(SWIFT_IMAGE) \
		bash -c 'setarch $$(uname -m) -R swift test --sanitize=address --scratch-path $(ASAN_SCRATCH)'

placeholders: ## List go-live placeholders still in code (GO-LIVE GL-02)
	scripts/go-live/find-placeholders.sh

# CS-06 (crash-safety.md): digest-pinned SwiftLint, scoped to packages/TallyCore/Sources and
# packages/TallyAppleKit/Sources (.swiftlint-crash-safety.yml). --strict makes a lint warning
# fail the build too, not just an error.
SWIFTLINT_IMAGE ?= ghcr.io/realm/swiftlint@sha256:1253e237c30010090484c50ae3ffe6f3be92ff17cebd71039420388f4199f03e # 0.59.1

.PHONY: lint

lint: ## Lint TallyCore + TallyAppleKit shipping code (force_unwrapping/force_try/force_cast/IUO)
	$(CONTAINER) run --rm --network none -v $(CURDIR):/repo:Z -w /repo $(SWIFTLINT_IMAGE) \
		swiftlint lint --strict --config .swiftlint-crash-safety.yml

# ------------------------------------------------------------------------------------------------
# iOS targets (perf-app-runtime.md §6). macOS with Xcode only: the Linux host cannot run these, so
# CI's macOS jobs call them. Result bundles and logs go to IOS_OUT (build/ios by default, ignored
# by git). Every test target prints each xcresult failure in full afterwards, whatever the result
# (scripts/ci/print_xcresult_failures.py: xcodebuild's console keeps only a failure's first line,
# and for a UI test the lines it drops are the accessibility hierarchy), then fails unless
# xcodebuild reported success.
# ------------------------------------------------------------------------------------------------
IOS_PROJECT_DIR := $(CURDIR)/apps/TallyiOS
IOS_OUT         ?= $(CURDIR)/build/ios
IOS_DERIVED     ?= $(IOS_OUT)/DerivedData
# The simulator is picked by script, never a hard-coded device name (architecture.md §3.6).
IOS_SIM_UDID    ?= $(shell python3 $(CURDIR)/scripts/ci/pick_ios_simulator.py 2>/dev/null | sed -n 's/^udid=//p')
# Optional test scope, e.g. IOS_ONLY_TESTING=-only-testing:TallyAppTests.
IOS_ONLY_TESTING ?=
# Which result bundle and log a test target writes (the deployment-floor run uses its own).
IOS_RESULT_NAME ?= Tally
IOS_XCODEBUILD   = xcodebuild -project $(IOS_PROJECT_DIR)/Tally.xcodeproj -scheme Tally
# A per-test hang limit (ios-ui-hang, folded into every test run): a hung test fails at 120 s
# (300 s if a test raises its own allowance) instead of eating the job's timeout, and no
# 600-second `simctl diagnose` runs after a failure.
IOS_TEST_FLAGS   = -collect-test-diagnostics never -test-timeouts-enabled YES \
                   -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 300
IOS_TEST_SUCCESS = "\*\* TEST (EXECUTE )?SUCCEEDED \*\*"
IOS_CONSOLE      = "error:|Test Suite|BUILD (SUCCEEDED|FAILED)| passed| failed"

.PHONY: ios-project ios-build-for-testing ios-test ios-tsan ios-asan ios-perf ios-summary ios-watchdog-log

ios-project: ## Generate apps/TallyiOS/Tally.xcodeproj with XcodeGen
	cd $(IOS_PROJECT_DIR) && xcodegen generate --spec project.yml

ios-build-for-testing: ## Build the app, TallyAppTests and TallyUITests for the iOS simulator
	@mkdir -p $(IOS_OUT)
	$(IOS_XCODEBUILD) build-for-testing -destination 'generic/platform=iOS Simulator' -derivedDataPath $(IOS_DERIVED) \
		| tee $(IOS_OUT)/build-for-testing.log | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" || true
	grep -q "BUILD SUCCEEDED" $(IOS_OUT)/build-for-testing.log

ios-test: ## Run the built tests on IOS_SIM_UDID with hang limits; print every failure in full
	@test -n "$(IOS_SIM_UDID)" || { echo "No iOS simulator picked (IOS_SIM_UDID is empty)"; exit 1; }
	@mkdir -p $(IOS_OUT)
	rm -rf $(IOS_OUT)/$(IOS_RESULT_NAME).xcresult
	$(IOS_XCODEBUILD) test-without-building -destination 'platform=iOS Simulator,id=$(IOS_SIM_UDID)' \
		-derivedDataPath $(IOS_DERIVED) $(IOS_ONLY_TESTING) \
		-resultBundlePath $(IOS_OUT)/$(IOS_RESULT_NAME).xcresult $(IOS_TEST_FLAGS) \
		| tee $(IOS_OUT)/$(IOS_RESULT_NAME)-test.log | grep -E $(IOS_CONSOLE) || true
	@$(MAKE) --no-print-directory ios-summary IOS_RESULT=$(IOS_OUT)/$(IOS_RESULT_NAME).xcresult
	grep -qE $(IOS_TEST_SUCCESS) $(IOS_OUT)/$(IOS_RESULT_NAME)-test.log

ios-tsan: ## TallyAppTests under ThreadSanitizer: fails on a test failure or any TSan report
	@test -n "$(IOS_SIM_UDID)" || { echo "No iOS simulator picked (IOS_SIM_UDID is empty)"; exit 1; }
	@mkdir -p $(IOS_OUT)
	rm -rf $(IOS_OUT)/Tally-tsan.xcresult
	$(IOS_XCODEBUILD) test -destination 'platform=iOS Simulator,id=$(IOS_SIM_UDID)' \
		-derivedDataPath $(IOS_OUT)/DerivedData-tsan -enableThreadSanitizer YES -only-testing:TallyAppTests \
		-resultBundlePath $(IOS_OUT)/Tally-tsan.xcresult $(IOS_TEST_FLAGS) \
		2>&1 | tee $(IOS_OUT)/tsan.log | grep -E $(IOS_CONSOLE)"|ThreadSanitizer" || true
	@$(MAKE) --no-print-directory ios-summary IOS_RESULT=$(IOS_OUT)/Tally-tsan.xcresult
	grep -qE $(IOS_TEST_SUCCESS) $(IOS_OUT)/tsan.log
	! grep -q "ThreadSanitizer:" $(IOS_OUT)/tsan.log

ios-asan: ## App + UI tests under AddressSanitizer: fails on a test failure or any ASan report
	@test -n "$(IOS_SIM_UDID)" || { echo "No iOS simulator picked (IOS_SIM_UDID is empty)"; exit 1; }
	@mkdir -p $(IOS_OUT)
	rm -rf $(IOS_OUT)/Tally-asan.xcresult
	$(IOS_XCODEBUILD) test -destination 'platform=iOS Simulator,id=$(IOS_SIM_UDID)' \
		-derivedDataPath $(IOS_OUT)/DerivedData-asan -enableAddressSanitizer YES \
		-resultBundlePath $(IOS_OUT)/Tally-asan.xcresult $(IOS_TEST_FLAGS) \
		2>&1 | tee $(IOS_OUT)/asan.log | grep -E $(IOS_CONSOLE)"|AddressSanitizer" || true
	@$(MAKE) --no-print-directory ios-summary IOS_RESULT=$(IOS_OUT)/Tally-asan.xcresult
	grep -qE $(IOS_TEST_SUCCESS) $(IOS_OUT)/asan.log
	! grep -q "ERROR: AddressSanitizer" $(IOS_OUT)/asan.log

# Release, like the charter's budgets; ENABLE_TESTABILITY lets the hosted tests `@testable import`.
IOS_PERF_TESTS ?= -only-testing:TallyAppTests/SampleLoadPerformanceTests

ios-perf: ## Release perf tests, then compare medians with perf/budgets.json
	@test -n "$(IOS_SIM_UDID)" || { echo "No iOS simulator picked (IOS_SIM_UDID is empty)"; exit 1; }
	@mkdir -p $(IOS_OUT)
	rm -rf $(IOS_OUT)/Tally-perf.xcresult
	$(IOS_XCODEBUILD) build-for-testing -configuration Release ENABLE_TESTABILITY=YES \
		-destination 'generic/platform=iOS Simulator' -derivedDataPath $(IOS_OUT)/DerivedData-perf \
		| tee $(IOS_OUT)/build-perf.log | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
	grep -q "BUILD SUCCEEDED" $(IOS_OUT)/build-perf.log
	$(IOS_XCODEBUILD) test-without-building -configuration Release \
		-destination 'platform=iOS Simulator,id=$(IOS_SIM_UDID)' -derivedDataPath $(IOS_OUT)/DerivedData-perf \
		$(IOS_PERF_TESTS) -resultBundlePath $(IOS_OUT)/Tally-perf.xcresult $(IOS_TEST_FLAGS) \
		| tee $(IOS_OUT)/perf.log | grep -E $(IOS_CONSOLE) || true
	@$(MAKE) --no-print-directory ios-summary IOS_RESULT=$(IOS_OUT)/Tally-perf.xcresult
	grep -qE $(IOS_TEST_SUCCESS) $(IOS_OUT)/perf.log
	xcrun xcresulttool get test-results metrics --path $(IOS_OUT)/Tally-perf.xcresult --compact \
		> $(IOS_OUT)/perf-metrics.json
	python3 $(CURDIR)/scripts/ci/check_perf_budgets.py $(CURDIR)/perf/budgets.json $(IOS_OUT)/perf-metrics.json

ios-watchdog-log: ## Print the DEBUG main-thread watchdog's lines from IOS_SIM_UDID's log (stalls: phase, ms)
	@test -n "$(IOS_SIM_UDID)" || { echo "No iOS simulator picked (IOS_SIM_UDID is empty)"; exit 1; }
	@xcrun simctl bootstatus $(IOS_SIM_UDID) -b > /dev/null 2>&1 || true
	@xcrun simctl spawn $(IOS_SIM_UDID) log show --style compact --last 3h \
		--predicate 'subsystem == "dev.tally-app.tally" AND category == "watchdog"' 2>&1 \
		| grep -E "main_thread_(stall|hang)" || echo "No main-thread stalls past the hang threshold were logged."

ios-summary: ## Print an xcresult's counts and every failure in full (IOS_RESULT=path)
	@if [ -d "$(IOS_RESULT)" ]; then \
		xcrun xcresulttool get test-results summary --path "$(IOS_RESULT)" --compact --format json \
			> "$(IOS_RESULT).summary.json" || true; \
		python3 $(CURDIR)/scripts/ci/print_xcresult_failures.py "$(IOS_RESULT).summary.json"; \
	else \
		echo "No result bundle at $(IOS_RESULT)"; \
	fi
