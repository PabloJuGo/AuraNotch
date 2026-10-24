# Contributing

Contributions are welcome. Please open an issue first for anything larger than a small fix.

- Requirements: macOS 14+ and Swift 6 (the Command Line Tools are enough, Xcode is not required).
- Build and test: `swift build`, then `swift run AuraSelfTests` (detailed failures) or `swift test`. Run `swift run AuraNotch --selftest-window` for the window smoke test.
- Translations live in `Resources/<language>.lproj`. Spanish (`es.lproj`) is the source: add every new string there and run `Scripts/check-localizations.py` to see what is missing in the other languages.
- Keep commits small and PRs reviewable, with build and tests green.
- Architecture overview: [ARCHITECTURE.md](ARCHITECTURE.md) (in Spanish). Design decisions: [Docs/decisions](Docs/decisions).
- Original implementation only: do not copy code, assets or branding from other apps.
