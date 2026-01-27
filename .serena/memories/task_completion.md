# Task Completion Checklist

When completing a task, ensure the following steps are performed:

## 1. Code Quality
- [ ] Run `./Scripts/format.sh` to auto-format code
- [ ] Check for SwiftLint violations: `swiftlint`
- [ ] Fix any linting errors before committing

## 2. Testing
- [ ] Run unit tests: `swift test`
- [ ] For significant changes, run comprehensive tests: `./Scripts/run-comprehensive-tests.sh`
- [ ] Add new tests for new functionality

## 3. Build Verification
- [ ] Ensure the project builds: `swift build`
- [ ] Test the app runs correctly: `swift run`

## 4. Code Review Considerations
- [ ] Ensure privacy compliance (no PII in logs)
- [ ] Check for proper error handling
- [ ] Verify thread safety for concurrent operations
- [ ] Confirm backward compatibility of changes

## 5. Documentation
- [ ] Update relevant documentation if behavior changes
- [ ] Add inline comments for complex logic