#!/usr/bin/env bash

set -Eeuo pipefail

readonly CHANGELOG="CHANGELOG.md"
readonly SPEC="vmware.spec"
readonly REPO_URL="https://github.com/hhlp/vmware"

usage() {
    cat <<'EOF'
Usage:
    ./scripts/prepare-release.sh VERSION

Example:
    ./scripts/prepare-release.sh 1.0.1

The script:

    1. Reads the current [Unreleased] section from CHANGELOG.md
    2. Creates the new release section
    3. Updates Version: in vmware.spec
    4. Generates the RPM %changelog entry
    5. Updates CHANGELOG comparison links
    6. Validates the generated CHANGELOG
    7. Validates the generated SPEC
    8. Validates the SPEC with rpmspec when available

The script does NOT:

    - commit changes
    - create a Git tag
    - push anything
    - create the GitHub Release
    - trigger a COPR build

Those operations remain explicit so the generated release can be
reviewed before publication.
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

# ------------------------------------------------------------
# Arguments
# ------------------------------------------------------------

if [[ $# -ne 1 ]]; then
    usage
    exit 1
fi

VERSION="$1"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "Invalid version: $VERSION (expected X.Y.Z)"
fi

# ------------------------------------------------------------
# Required files
# ------------------------------------------------------------

[[ -f "$CHANGELOG" ]] || die "$CHANGELOG not found"
[[ -f "$SPEC" ]] || die "$SPEC not found"

# ------------------------------------------------------------
# Git repository
# ------------------------------------------------------------

git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    die "This command must be run inside a Git repository"

# ------------------------------------------------------------
# Determine current version
# ------------------------------------------------------------

CURRENT_VERSION="$(
    awk '
        $1 == "Version:" {
            print $2
            exit
        }
    ' "$SPEC"
)"

[[ -n "$CURRENT_VERSION" ]] ||
    die "Unable to determine current Version from $SPEC"

if [[ ! "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "Invalid current Version in $SPEC: $CURRENT_VERSION"
fi

if [[ "$VERSION" == "$CURRENT_VERSION" ]]; then
    die "Version $VERSION is already present in $SPEC"
fi

if grep -Fq "## [$VERSION]" "$CHANGELOG"; then
    die "Version $VERSION already exists in $CHANGELOG"
fi

# ------------------------------------------------------------
# Release metadata
# ------------------------------------------------------------

RELEASE_DATE="$(date '+%Y-%m-%d')"
RPM_DATE="$(LC_ALL=C date '+%a %b %d %Y')"

RPM_CHANGELOG_NAME="${RPM_CHANGELOG_NAME:-$(git config user.name || true)}"
RPM_CHANGELOG_EMAIL="${RPM_CHANGELOG_EMAIL:-$(git config user.email || true)}"

[[ -n "$RPM_CHANGELOG_NAME" ]] ||
    die "Unable to determine RPM changelog name. Configure git user.name or RPM_CHANGELOG_NAME."

[[ -n "$RPM_CHANGELOG_EMAIL" ]] ||
    die "Unable to determine RPM changelog email. Configure git user.email or RPM_CHANGELOG_EMAIL."

# ------------------------------------------------------------
# Temporary working directory
# ------------------------------------------------------------

TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

UNRELEASED_BODY="$TMP_DIR/unreleased.txt"
RPM_ITEMS="$TMP_DIR/rpm-items.txt"
NEW_CHANGELOG="$TMP_DIR/CHANGELOG.md"
NEW_CHANGELOG_LINKS="$TMP_DIR/CHANGELOG-links.md"
NEW_SPEC="$TMP_DIR/vmware.spec"
NEW_SPEC_WITH_CHANGELOG="$TMP_DIR/vmware-with-changelog.spec"

# ------------------------------------------------------------
# Extract [Unreleased]
# ------------------------------------------------------------

awk '
    /^## \[Unreleased\]$/ {
        found = 1
        next
    }

    found && /^## \[[^]]+\]/ {
        exit
    }

    found && /^---$/ {
        next
    }

    found {
        print
    }
' "$CHANGELOG" > "$UNRELEASED_BODY"

grep -qE '^[[:space:]]*[-*+][[:space:]]+' "$UNRELEASED_BODY" ||
    die "CHANGELOG.md [Unreleased] contains no release entries"

# ------------------------------------------------------------
# Convert Markdown release bullets into RPM changelog bullets.
#
# Supported:
#
# - Entry
# * Entry
# + Entry
#
# Wrapped indented lines are joined to the current RPM item.
# ------------------------------------------------------------

awk '
    function flush_item() {
        if (item != "") {
            print "- " item
            item = ""
        }
    }

    /^[[:space:]]*[-*+][[:space:]]+/ {
        flush_item()

        line = $0
        sub(/^[[:space:]]*[-*+][[:space:]]+/, "", line)

        item = line
        next
    }

    item != "" && /^[[:space:]]+/ {
        line = $0
        sub(/^[[:space:]]+/, "", line)

        if (
            line != "" &&
            line !~ /^```/ &&
            line !~ /^###/
        ) {
            item = item " " line
        }

        next
    }

    {
        flush_item()
    }

    END {
        flush_item()
    }
' "$UNRELEASED_BODY" > "$RPM_ITEMS"

[[ -s "$RPM_ITEMS" ]] ||
    die "Unable to generate RPM changelog entries"

# ------------------------------------------------------------
# Create new CHANGELOG release section.
#
# The existing [Unreleased] body becomes the new release body.
#
# Before:
#
# ## [Unreleased]
#
# ### Fixed
#
# - Some fix.
#
# ---
#
# ## [1.0.0] - ...
#
# After:
#
# ## [Unreleased]
#
# ---
#
# ## [1.0.1] - YYYY-MM-DD
#
# ### Fixed
#
# - Some fix.
#
# ---
#
# ## [1.0.0] - ...
# ------------------------------------------------------------

awk -v version="$VERSION" -v date="$RELEASE_DATE" '
    /^## \[Unreleased\]$/ {
        print
        print ""
        print "---"
        print ""
        print "## [" version "] - " date
        next
    }

    {
        print
    }
' "$CHANGELOG" > "$NEW_CHANGELOG"

# ------------------------------------------------------------
# Update CHANGELOG comparison links.
#
# Before:
#
# [Unreleased]: https://github.com/hhlp/vmware/compare/v1.0.0...HEAD
#
# After:
#
# [Unreleased]: https://github.com/hhlp/vmware/compare/v1.0.1...HEAD
# [1.0.1]: https://github.com/hhlp/vmware/compare/v1.0.0...v1.0.1
# ------------------------------------------------------------

EXPECTED_UNRELEASED_LINK="$(
    printf '%s/compare/v%s...HEAD' "$REPO_URL" "$CURRENT_VERSION"
)"

NEW_UNRELEASED_LINK="$(
    printf '%s/compare/v%s...HEAD' "$REPO_URL" "$VERSION"
)"

NEW_RELEASE_LINK="$(
    printf '%s/compare/v%s...v%s' "$REPO_URL" "$CURRENT_VERSION" "$VERSION"
)"

grep -Fq "[Unreleased]: $EXPECTED_UNRELEASED_LINK" "$NEW_CHANGELOG" ||
    die "Unable to locate expected [Unreleased] comparison link: $EXPECTED_UNRELEASED_LINK"

awk -v old="[Unreleased]: $EXPECTED_UNRELEASED_LINK" -v unreleased="[Unreleased]: $NEW_UNRELEASED_LINK" -v release="[$VERSION]: $NEW_RELEASE_LINK" '
    $0 == old {
        print unreleased
        print release
        next
    }

    {
        print
    }
' "$NEW_CHANGELOG" > "$NEW_CHANGELOG_LINKS"

mv "$NEW_CHANGELOG_LINKS" "$NEW_CHANGELOG"

# ------------------------------------------------------------
# Update SPEC Version
# ------------------------------------------------------------

awk -v version="$VERSION" '
    $1 == "Version:" {
        printf "%-15s %s\n", "Version:", version
        next
    }

    {
        print
    }
' "$SPEC" > "$NEW_SPEC"

# ------------------------------------------------------------
# Generate RPM %changelog header
# ------------------------------------------------------------

RPM_HEADER="$(
    printf '* %s %s <%s> - %s-1' "$RPM_DATE" "$RPM_CHANGELOG_NAME" "$RPM_CHANGELOG_EMAIL" "$VERSION"
)"

# ------------------------------------------------------------
# Add RPM %changelog entry
# ------------------------------------------------------------

awk -v header="$RPM_HEADER" -v items="$RPM_ITEMS" '
    {
        print
    }

    $0 == "%changelog" {
        print header

        while ((getline line < items) > 0) {
            print line
        }

        close(items)
        print ""
    }
' "$NEW_SPEC" > "$NEW_SPEC_WITH_CHANGELOG"

mv "$NEW_SPEC_WITH_CHANGELOG" "$NEW_SPEC"

# ------------------------------------------------------------
# Validate generated CHANGELOG
# ------------------------------------------------------------

grep -Fq "## [$VERSION] - $RELEASE_DATE" "$NEW_CHANGELOG" ||
    die "Generated CHANGELOG does not contain release $VERSION"

grep -Fq "[Unreleased]: $NEW_UNRELEASED_LINK" "$NEW_CHANGELOG" ||
    die "Generated CHANGELOG has invalid [Unreleased] link"

grep -Fq "[$VERSION]: $NEW_RELEASE_LINK" "$NEW_CHANGELOG" ||
    die "Generated CHANGELOG has no comparison link for $VERSION"

# ------------------------------------------------------------
# Validate generated SPEC version
# ------------------------------------------------------------

GENERATED_VERSION="$(
    awk '
        $1 == "Version:" {
            print $2
            exit
        }
    ' "$NEW_SPEC"
)"

[[ -n "$GENERATED_VERSION" ]] ||
    die "Unable to read Version from generated SPEC"

[[ "$GENERATED_VERSION" == "$VERSION" ]] ||
    die "Generated SPEC version is $GENERATED_VERSION instead of $VERSION"

# ------------------------------------------------------------
# Validate generated RPM changelog
# ------------------------------------------------------------

grep -Fq "$RPM_HEADER" "$NEW_SPEC" ||
    die "Generated SPEC does not contain the expected RPM changelog entry"

# ------------------------------------------------------------
# Validate %changelog exists exactly once
# ------------------------------------------------------------

CHANGELOG_COUNT="$(
    grep -c '^%changelog$' "$NEW_SPEC" || true
)"

[[ "$CHANGELOG_COUNT" -eq 1 ]] ||
    die "Generated SPEC must contain exactly one %changelog section"

# ------------------------------------------------------------
# Validate generated SPEC with rpmspec
# ------------------------------------------------------------

if command -v rpmspec >/dev/null 2>&1; then
    rpmspec -P "$NEW_SPEC" >/dev/null ||
        die "Generated SPEC failed rpmspec validation"
else
    printf '%s\n' "WARNING: rpmspec is not installed; SPEC validation skipped." >&2
fi

# ------------------------------------------------------------
# Install generated files.
#
# Repository files are modified only after every transformation
# and validation step has completed successfully.
# ------------------------------------------------------------

cp "$NEW_CHANGELOG" "$CHANGELOG"
cp "$NEW_SPEC" "$SPEC"

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

printf '\n'
printf '%s\n' 'Release preparation complete.'
printf '\n'

printf '  Previous version : %s\n' "$CURRENT_VERSION"
printf '  New version      : %s\n' "$VERSION"
printf '  Release date     : %s\n' "$RELEASE_DATE"
printf '  RPM changelog    : %s <%s>\n' "$RPM_CHANGELOG_NAME" "$RPM_CHANGELOG_EMAIL"

printf '\n'
printf '%s\n' 'Updated:'
printf '  %s\n' "$CHANGELOG"
printf '  %s\n' "$SPEC"

printf '\n'
printf '%s\n' 'Review the result:'
printf '\n'
printf '  git diff -- %s %s\n' "$CHANGELOG" "$SPEC"

printf '\n'
printf '%s\n' 'Run validation:'
printf '\n'
printf '%s\n' '  bash -n scripts/prepare-release.sh'
printf '%s\n' '  shellcheck scripts/prepare-release.sh'
printf '  rpmspec -P %s >/dev/null\n' "$SPEC"

printf '\n'
printf '%s\n' 'If everything is correct:'
printf '\n'

printf '  git add %s %s\n' "$CHANGELOG" "$SPEC"
printf '  git commit -m "chore: prepare v%s release"\n' "$VERSION"
printf '  git tag -s "v%s" -m "v%s"\n' "$VERSION" "$VERSION"
printf '%s\n' '  git push origin main'
printf '  git push origin "v%s"\n' "$VERSION"

printf '\n'