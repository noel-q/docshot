#!/bin/bash
#
# Audits the Xcode DocShotTests target against Tests/target-parity.json.
#
# The Xcode test bundle is hostless: it links no app binary and instead compiles a
# curated subset of production sources directly. Nothing in Xcode enforces that subset,
# and a test file that is missing from the target is skipped *silently* — `xcodebuild
# test` still reports success. This audit is what makes that drift loud.
#
# Exits non-zero on any finding. See docs/TEST_ARCHITECTURE.md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec /usr/bin/env python3 - "$REPO_ROOT" <<'PYTHON'
import json
import os
import re
import sys

repo = sys.argv[1]
manifest_path = os.path.join(repo, "Tests", "target-parity.json")
pbxproj_path = os.path.join(repo, "DocShot.xcodeproj", "project.pbxproj")

failures = []
notes = []


def fail(title, detail=""):
    failures.append((title, detail))


def bullets(paths):
    return "\n".join("      - %s" % p for p in sorted(paths))


# ---------------------------------------------------------------- inputs

try:
    with open(manifest_path) as handle:
        manifest = json.load(handle)
except (OSError, ValueError) as error:
    print("audit-test-parity: cannot read Tests/target-parity.json: %s" % error)
    sys.exit(2)

try:
    with open(pbxproj_path) as handle:
        pbxproj = handle.read()
except OSError as error:
    print("audit-test-parity: cannot read project.pbxproj: %s" % error)
    sys.exit(2)

app_target = manifest["appTarget"]
test_target = manifest["testTarget"]
test_dir = manifest["testSourceDirectory"]
source_dir = manifest["productionSourceDirectory"]


# ---------------------------------------------------------------- pbxproj

# A parse that comes up empty means the project format moved under us. Treat that as a
# failure rather than letting the audit pass by finding nothing.

build_files = dict(
    re.findall(
        r"^\t\t(\w+) /\* .*? in Sources \*/ = \{isa = PBXBuildFile; fileRef = (\w+)",
        pbxproj,
        re.M,
    )
)
file_refs = dict(
    re.findall(
        r"^\t\t(\w+) /\* .*? \*/ = \{isa = PBXFileReference;.*? path = ([^;]+);",
        pbxproj,
        re.M,
    )
)
if not build_files or not file_refs:
    print("audit-test-parity: could not parse PBXBuildFile/PBXFileReference entries; "
          "the project format may have changed.")
    sys.exit(2)

sources_phases = {
    phase_id: files
    for phase_id, files in re.findall(
        r"(\w+) /\* Sources \*/ = \{\s*isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);",
        pbxproj,
        re.S,
    )
}

native_targets = {}
for target_id, target_name, body in re.findall(
    r"(\w+) /\* (\w+) \*/ = \{\s*isa = PBXNativeTarget;(.*?)\n\t\t\};", pbxproj, re.S
):
    phase_ids = []
    phases_block = re.search(r"buildPhases = \((.*?)\);", body, re.S)
    if phases_block:
        phase_ids = re.findall(r"(\w+) /\*", phases_block.group(1))
    native_targets[target_name] = phase_ids


def compiled_files(target_name):
    """Every file compiled by that target's Sources phase, as repo-relative paths."""
    if target_name not in native_targets:
        print("audit-test-parity: target %r not found in project.pbxproj." % target_name)
        sys.exit(2)
    for phase_id in native_targets[target_name]:
        if phase_id in sources_phases:
            entries = re.findall(r"(\w+) /\*", sources_phases[phase_id])
            return {file_refs[build_files[e]] for e in entries if e in build_files}
    print("audit-test-parity: no Sources phase found for target %r." % target_name)
    sys.exit(2)


app_compiled = compiled_files(app_target)
test_compiled = compiled_files(test_target)


# ---------------------------------------------------------------- disk

def swift_files(relative_dir):
    root = os.path.join(repo, relative_dir)
    found = set()
    for dirpath, _, filenames in os.walk(root):
        for name in filenames:
            if name.endswith(".swift"):
                absolute = os.path.join(dirpath, name)
                found.add(os.path.relpath(absolute, repo))
    return found


tests_on_disk = swift_files(test_dir)
sources_on_disk = swift_files(source_dir)


# ------------------------------------------- 1. test files must all be in the target

tests_in_target = {p for p in test_compiled if p.startswith(test_dir + "/")}

missing_from_target = tests_on_disk - tests_in_target
if missing_from_target:
    fail(
        "Test files on disk are not compiled by the %s target." % test_target,
        "      These run under `swift test` and are SILENTLY SKIPPED by `xcodebuild test`,\n"
        "      which still reports success. Add them to the target's Sources phase.\n"
        + bullets(missing_from_target),
    )

missing_from_disk = tests_in_target - tests_on_disk
if missing_from_disk:
    fail(
        "The %s target references test files that no longer exist." % test_target,
        bullets(missing_from_disk),
    )


# --------------------------------- 2. duplicated / app-only membership vs manifest

declared_duplicated = set(manifest["duplicatedProductionSources"])
declared_app_only = set(manifest["appOnlyProductionSources"])

actual_duplicated = {p for p in test_compiled if p.startswith(source_dir + "/")}
actual_app_only = {p for p in app_compiled - test_compiled if p.startswith(source_dir + "/")}

undeclared = actual_duplicated - declared_duplicated
if undeclared:
    fail(
        "Production sources are compiled into %s but not declared as duplicated."
        % test_target,
        "      Each copy is compiled into the test module and shadows the app's own type.\n"
        "      Declare it in Tests/target-parity.json if the duplication is intended.\n"
        + bullets(undeclared),
    )

stale = declared_duplicated - actual_duplicated
if stale:
    fail(
        "Manifest declares duplicated sources that %s no longer compiles." % test_target,
        bullets(stale),
    )

app_only_undeclared = actual_app_only - declared_app_only
if app_only_undeclared:
    fail(
        "Production sources are app-only but not declared as such.",
        "      Nothing in the Xcode test bundle can reach these symbols.\n"
        + bullets(app_only_undeclared),
    )

app_only_stale = declared_app_only - actual_app_only
if app_only_stale:
    fail(
        "Manifest declares app-only sources that are no longer app-only.",
        bullets(app_only_stale),
    )

# A production file in neither list is in no Xcode target at all: SwiftPM builds it,
# Xcode does not, and the divergence is invisible until something fails to resolve.
orphaned = sources_on_disk - actual_duplicated - actual_app_only
if orphaned:
    fail(
        "Production sources are in no Xcode target.",
        "      `swift test` compiles these; the Xcode project does not see them.\n"
        + bullets(orphaned),
    )


# ------------------------------------- 3. #if SWIFT_PACKAGE suites must be declared

def guarded_suites(path, unparseable):
    """`(suite name, @Test count)` for each suite inside an `#if SWIFT_PACKAGE` region.

    Deliberately strict. A suite whose name or body this cannot identify is appended to
    `unparseable` rather than skipped: a parser that no longer understands the file must
    fail the audit, not quietly report zero SwiftPM-only suites.
    """
    found = []
    stack = []  # one entry per open #if: True when SWIFT_PACKAGE is currently active
    with open(os.path.join(repo, path)) as handle:
        lines = handle.read().splitlines()

    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("#if "):
            stack.append(stripped[4:].strip() == "SWIFT_PACKAGE")
            continue
        if stripped.startswith("#elseif ") or stripped == "#else":
            if stack:
                stack[-1] = False
            continue
        if stripped == "#endif":
            if stack:
                stack.pop()
            continue
        if not any(stack) or stripped.startswith("//") or "@Suite" not in stripped:
            continue

        where = "%s:%d" % (path, index + 1)
        name_match = re.search(r'@Suite\(\s*"([^"]*)"', stripped)
        if not name_match:
            unparseable.append("%s: cannot read a suite name from %r" % (where, stripped))
            continue
        name = name_match.group(1)

        # The suite's tests are the `@Test` declarations inside its type body. Find the
        # opening brace (attributes such as `@MainActor` may sit between), then track
        # depth to the matching close.
        body_start = None
        for offset in range(index, min(index + 6, len(lines))):
            if "{" in lines[offset]:
                body_start = offset
                break
        if body_start is None:
            unparseable.append("%s: no body found for suite %r" % (where, name))
            continue

        depth = 0
        count = 0
        closed = False
        for body_line in lines[body_start:]:
            if depth > 0 and body_line.strip().startswith("@Test"):
                count += 1
            depth += body_line.count("{") - body_line.count("}")
            if depth <= 0:
                closed = True
                break
        if not closed:
            unparseable.append("%s: braces never balance for suite %r" % (where, name))
            continue

        found.append((name, count))

    return found


declared_suites = {}
for entry in manifest["swiftPackageOnlySuites"]:
    key = (entry["file"], entry["suite"])
    if not isinstance(entry.get("testCount"), int):
        print(
            "audit-test-parity: manifest entry %r is missing an integer testCount." % (key,)
        )
        sys.exit(2)
    declared_suites[key] = entry["testCount"]

unparseable_suites = []
actual_suites = {}
for path in sorted(tests_on_disk):
    for suite, test_count in guarded_suites(path, unparseable_suites):
        actual_suites[(path, suite)] = test_count

if unparseable_suites:
    print("audit-test-parity: could not identify the structure of a guarded suite; "
          "refusing to report parity.")
    for problem in unparseable_suites:
        print("  %s" % problem)
    sys.exit(2)

miscounted = [
    (key, declared_suites[key], actual_suites[key])
    for key in sorted(set(declared_suites) & set(actual_suites))
    if declared_suites[key] != actual_suites[key]
]
if miscounted:
    fail(
        "Declared testCount does not match the suite's `@Test` declarations.",
        "      The manifest is the record of how large the intentional delta is; a stale\n"
        "      count hides tests appearing in or vanishing from a SwiftPM-only suite.\n"
        + "\n".join(
            "      - %s :: %s declares %d, found %d" % (f, s, declared, actual)
            for (f, s), declared, actual in miscounted
        ),
    )

suites_undeclared = set(actual_suites) - set(declared_suites)
if suites_undeclared:
    fail(
        "SwiftPM-only test suites are not declared in the manifest.",
        "      A `#if SWIFT_PACKAGE` suite does not run under `xcodebuild test`.\n"
        "      Declare it with a reason, or make it run in both toolchains.\n"
        + bullets("%s :: %s" % (f, s) for f, s in suites_undeclared),
    )

suites_stale = set(declared_suites) - set(actual_suites)
if suites_stale:
    fail(
        "Manifest declares SwiftPM-only suites that no longer exist as declared.",
        bullets("%s :: %s" % (f, s) for f, s in suites_stale),
    )


# ---------------------------------------------------------------- report

notes.append("%-3d test files compiled by both toolchains" % len(tests_on_disk))
notes.append("%-3d production sources duplicated into %s" % (len(actual_duplicated), test_target))
notes.append("%-3d production sources app-only" % len(actual_app_only))
notes.append(
    "%-3d SwiftPM-only suite(s) declared: %s"
    % (
        len(declared_suites),
        ", ".join(
            "%s (%d test%s)" % (suite, count, "" if count == 1 else "s")
            for (_, suite), count in sorted(declared_suites.items())
        )
        or "none",
    )
)

print("Test parity audit")
for note in notes:
    print("  %s" % note)

if failures:
    print("")
    for title, detail in failures:
        print("  FAIL: %s" % title)
        if detail:
            print(detail)
    print("")
    print("%d finding(s). See docs/TEST_ARCHITECTURE.md." % len(failures))
    sys.exit(1)

print("")
print("OK: the Xcode test target matches Tests/target-parity.json.")
PYTHON
