Lint pipeline currently has two separate paths:
1) swiftlint (full run) reports warnings for modifier_order/opening_brace/number_separator in several files but exits 0.
2) build gate uses Scripts/enforce-lint.sh (only custom test OverlayManager rules) plus swiftformat --lint.
Running swiftformat . fixed 29 files that were failing swiftformat --lint.