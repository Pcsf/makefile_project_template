# Sourced by the self-tests.
#
#   copy_fixture <name> <dest>   copy test/<name> into <dest> as a clone has it
#
# In a git work tree only tracked and untracked-but-not-ignored files are
# copied, so leftovers of an earlier run in the fixture (Makefile.mk
# fragments, build/) never reach the test. Outside git it is a plain copy.

copy_fixture() {
    local repo; repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$repo" ls-files -z -co --exclude-standard -- "test/$1" \
            | tar -C "$repo" --null -T - -cf - \
            | tar -C "$2" --strip-components=2 -xf -
    else
        cp -r "$repo/test/$1/." "$2/"
    fi
}
