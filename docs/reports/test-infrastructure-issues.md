# Test Infrastructure Issues — Starter Brief

**Project**: Unmissable (macOS menu bar app, Swift 6.0, SPM)
**Date**: 2026-04-03
**Context**: During a UI component library rebuild, running tests from Claude Code CLI exposed multiple infrastructure problems. All 585 tests pass, but the test runner setup is fragile and hostile to automated agents.

---

## Issue 1: `swift test` output not capturable by CLI tools

**Symptom**: `swift test` commands produce zero visible output when run from Claude Code's Bash tool. Commands appear to hang, get auto-backgrounded, and output files remain empty for minutes.

**Root cause**: Multiple compounding factors:
- `swift test` outputs test progress to **stderr**, not stdout. The Bash tool may not merge streams reliably for long-running processes.
- SPM's prebuild lint gate plugin (`LintGatePlugin`) runs first and blocks compilation if there are any lint errors. When this fails, `swift test` exits silently with no test output at all — it never reaches the test execution phase.
- Long-running commands (>2 minutes) get auto-backgrounded by Claude Code's Bash tool. The background task output capture writes to a file, but the file stays empty until the process exits because output is buffered.

**Impact**: An agent cannot tell if tests are compiling, running, passing, or failing. It flies blind.

**Desired fix**: A test runner wrapper that:
1. Separates compilation from test execution (build first, then test)
2. Streams output line-by-line to a file that can be tailed
3. Has a hard timeout (e.g. 5 minutes) so it never hangs indefinitely
4. Exits with clear status: `PASS (N tests)`, `FAIL (N failures)`, `BUILD_ERROR`, or `TIMEOUT`
5. Writes a machine-readable summary (JSON or single-line) that an agent can parse without reading hundreds of lines of XCTest output

---

## Issue 2: Zombie `swift-test` processes deadlock on SPM build lock

**Symptom**: After a failed or interrupted test run, subsequent `swift test` commands hang forever with zero output.

**Root cause**: SPM uses a file lock on `.build/`. If a `swift test` process is killed (e.g. by Claude Code's timeout, user interrupt, or `pkill`), the lock may not be released cleanly. The next `swift test` invocation waits indefinitely for the lock.

Additionally, when an agent retries a failing command multiple times, multiple `swift-test` processes pile up, all competing for the same lock. We observed 5 zombie processes in one session.

**Impact**: Complete test runner deadlock. No tests can run until all zombie processes are manually killed.

**Desired fix**:
1. The test wrapper script should check for and kill existing `swift-test` processes before starting
2. Consider `flock`-style timeout on the build directory lock
3. The script should have a `--clean` flag that removes `.build/Build` and retries

---

## Issue 3: No project-level config for parallel worker count

**Symptom**: Bare `swift test` spawns unlimited parallel workers, consuming all CPU cores and memory.

**Root cause**: SPM has no config file for test parallelism. The `--parallel --num-workers N` flags are CLI-only. There is [an open feature request](https://github.com/swiftlang/swift-package-manager/issues/4775) but no resolution.

**Current mitigation**: `Scripts/test.sh` enforces `--parallel --num-workers 4`. But anyone running bare `swift test` bypasses this.

**Desired fix**: The test wrapper is the only enforcement point. Document it aggressively. Consider adding a git hook or lint rule that warns if `swift test` appears in any script without `--num-workers`.

---

## Issue 4: xcodebuild cannot run tests (Package.swift structure)

**Symptom**: `xcodebuild -scheme Unmissable test` fails with `Target "UnmissableTests" depends on a test target ("TestSupport")`.

**Root cause**: `TestSupport` is declared as a `.testTarget` in Package.swift, and other test targets depend on it. SPM handles this fine, but xcodebuild's package graph resolver rejects test-target-depends-on-test-target.

**Impact**: The comprehensive test script (`Scripts/run-comprehensive-tests.sh`) uses xcodebuild and is broken. The `Scripts/build.sh` was updated to use `swift test` instead.

**Desired fix**: Change `TestSupport` from `.testTarget` to a regular `.target` (it contains no tests, only shared test doubles). This would make both `swift test` and `xcodebuild test` work.

---

## Issue 5: E2E tests are slow under parallel execution

**Symptom**: The test suite reaches ~507/585 tests quickly, then appears to hang for 30-60 seconds on `SchedulerTimerE2ETests`.

**Root cause**: E2E tests use `e2eWait(timeout: 5.0)` which polls every 100ms. Multiple E2E tests running in parallel each create their own `E2ETestEnvironment` with a temp database and `TestClock`. The polling loops consume wall-clock time even when the test clock auto-advances.

**Impact**: The full suite takes 3-4 minutes. Not a real hang, but looks like one to an impatient agent that times out at 2 minutes.

**Desired fix**:
1. Increase the Bash tool timeout when running full test suites
2. Consider running E2E tests sequentially (not in parallel) since they're inherently stateful
3. The test wrapper should emit periodic heartbeat lines so the agent knows it's still running

---

## Issue 6: Lint gate blocks test compilation silently

**Symptom**: `swift test` exits with an error code but prints only SwiftLint violations, no "test failed" message. An agent sees lint errors and thinks tests failed, when actually no tests ran.

**Root cause**: `LintGatePlugin` is a prebuild plugin on the test targets. If any lint rule fails, compilation is aborted before tests execute. The error output is swiftlint violations, not test results.

**Impact**: Confusing feedback loop — the agent tries to fix "test failures" when the actual problem is a lint violation.

**Desired fix**: The test wrapper should:
1. Run lint separately first and report `LINT_FAIL` distinctly from `TEST_FAIL`
2. Or: remove the lint gate from test targets and only enforce it on the main target (tests should compile even if lint fails, so you can run them to verify fixes)

---

## Recommended Test Wrapper: `Scripts/test.sh`

The ideal wrapper addresses all issues above:

```
Scripts/test.sh [filter]

1. Kill any existing swift-test processes
2. Run swiftlint — exit with LINT_FAIL if violations
3. Run swift build — exit with BUILD_FAIL if errors
4. Run swift test --parallel --num-workers 4 [--filter X]
   - Stream output to both terminal and a log file
   - Hard timeout of 5 minutes
   - Parse final line for pass/fail count
5. Print summary: PASS (585 tests, 0 failures, 47s) or FAIL (details)
6. Write machine-readable result to .build/test-result.json
```

Current `Scripts/test.sh` only does step 4. Steps 1-3 and 5-6 are missing.
