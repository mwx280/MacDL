# Contributing to MacDL

Thanks for considering contributing! This project is small, so a little structure goes a long way.

## Bugs

Open an issue with the **Bug report** template. Include:

- macOS version and app version
- What you expected vs. what happened
- Steps to reproduce
- Any relevant Console output

## Feature ideas

Open an issue with the **Feature request** template. Describe the problem you're
trying to solve, not just the feature — it helps us find a better solution.

## Pull requests

1. Fork the repo and create a branch (`feature/...` or `fix/...`).
2. Make your change.
3. Make sure both test suites pass:

   ```bash
   cd MacDLCore && swift test

   xcodebuild test -project MacDL.xcodeproj -scheme MacDL \
     -destination 'platform=macOS' -parallel-testing-enabled NO
   ```

4. Open a PR against `main`. Use the PR template and fill in the checklist.

### Notes

- Keep commit messages in natural English; the project history is intentionally clean.
- Comments in code should explain **why**, not what.
- This project is **GPL-3.0** — your contributions are licensed under the same terms.
