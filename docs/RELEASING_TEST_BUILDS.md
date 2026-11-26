# Releasing a test build

For Noel. Each release is public on github.com/noel-q/docshot and needs Noel's yes. Testers' copies of DocShot (1.1.0 build 2 and later) find it within a day and show the update guide.

## What the app looks for

- A GitHub release, not a draft, tagged `macos-v<version>-build.<n>`, for example `macos-v1.1.0-build.3`. Pre-releases count.
- `<n>` higher than the tester's build number (`CURRENT_PROJECT_VERSION` in the Xcode project).
- A `.dmg` file attached to the release.
- The release notes show in the guide as plain text, cut at about 400 characters. Keep them short: a heading and a few `- ` lines.

## Steps

1. Raise `CURRENT_PROJECT_VERSION` by one in `DocShot.xcodeproj/project.pbxproj` (both build settings blocks). Raise `MARKETING_VERSION` only for a bigger step.
2. Commit, then build: `Scripts/package-development-dmg.sh dist/test-<date>`.
3. Check the DMG as for any test build (signature, both architectures, no debug hooks).
4. With Noel's yes, publish:

   ```bash
   gh release create macos-v1.1.0-build.3 dist/test-<date>/DocShot-macos-development.dmg --repo noel-q/docshot --prerelease --title "Test build 3" --notes-file <notes.md>
   ```

## Know before publishing

- The DMG is public: anyone with the link can download it.
- It is signed with Noel's Apple Development certificate, whose name includes his Apple ID email. Anyone who inspects the signature can see it.
- It is not notarised, so every tester clicks Open Anyway after each update.
