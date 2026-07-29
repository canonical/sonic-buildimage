#!/bin/bash
# Self-test for patch_class(): uses minimal, hand-written valid
# unified diff snippets in a temp directory, covering every input
# shape scripts/ppa/patch-class.sh classifies, without depending on
# any real package's patch.
#
# This test is itself self-contained (the *_test.sh suffix, see the
# note in run-tests.sh), unlike test-build-source.sh, which needs a
# package name argument passed in.
set -euo pipefail

cd "$(dirname "$0")/../../.."
source scripts/ppa/patch-class.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0

# Only touches files under debian/ -> debian
cat > "$tmp/only_debian.patch" <<'EOF'
--- a/debian/rules
+++ b/debian/rules
@@ -1 +1 @@
-old
+new
EOF

# Only touches files outside debian/ -> upstream
cat > "$tmp/only_upstream.patch" <<'EOF'
--- a/src/foo.c
+++ b/src/foo.c
@@ -1 +1 @@
-old
+new
EOF

# One touches debian/, one touches upstream -> mixed
cat > "$tmp/one_of_each.patch" <<'EOF'
--- a/debian/rules
+++ b/debian/rules
@@ -1 +1 @@
-old
+new
--- a/src/foo.c
+++ b/src/foo.c
@@ -1 +1 @@
-old
+new
EOF

# Creates a new file under debian/ (--- /dev/null) -> debian
cat > "$tmp/create_debian.patch" <<'EOF'
--- /dev/null
+++ b/debian/newfile
@@ -0,0 +1 @@
+new content
EOF

# Deletes a file under debian/ (+++ /dev/null, real path is on the --- line) -> debian
cat > "$tmp/delete_debian.patch" <<'EOF'
--- a/debian/oldfile
+++ /dev/null
@@ -1 +0,0 @@
-old content
EOF

# Deletes a debian/ file while also touching an upstream file -> mixed
cat > "$tmp/delete_debian_plus_upstream.patch" <<'EOF'
--- a/debian/oldfile
+++ /dev/null
@@ -1 +0,0 @@
-old content
--- a/src/foo.c
+++ b/src/foo.c
@@ -1 +1 @@
-old
+new
EOF

# A single patch creates multiple files under debian/ (the shape seen in lm-sensors) -> debian
cat > "$tmp/multi_debian_creates.patch" <<'EOF'
--- /dev/null
+++ b/debian/newfile1
@@ -0,0 +1 @@
+new content
--- /dev/null
+++ b/debian/newfile2
@@ -0,0 +1 @@
+new content
--- /dev/null
+++ b/debian/newfile3
@@ -0,0 +1 @@
+new content
EOF

# Empty file: no "--- "/"+++ " header pair at all -> invalid, not the old
# fail-open "upstream" default.
: > "$tmp/empty.patch"

# -p0-style header, no a/ or b/ prefix at all -> invalid. Naively stripping
# "the first path component" from "debian/rules" here would strip
# "debian/" itself and misfile this as upstream instead of debian.
cat > "$tmp/p0_style.patch" <<'EOF'
--- debian/rules
+++ debian/rules
@@ -1 +1 @@
-old
+new
EOF

check() {
    local name="$1" file="$2" want="$3" got
    got="$(patch_class "$tmp/$file")"
    if [ "$got" = "$want" ]; then
        echo "ok   $name -> $got"
    else
        echo "FAIL $name: want $want, got $got"
        fail=1
    fi
}

check "modifies only debian/"                       only_debian.patch                  debian
check "modifies only upstream"                       only_upstream.patch                upstream
check "modifies one debian/ + one upstream"          one_of_each.patch                  mixed
check "creates a new debian/ file"                   create_debian.patch                debian
check "deletes a debian/ file"                       delete_debian.patch                debian
check "deletes a debian/ file + modifies upstream"   delete_debian_plus_upstream.patch  mixed
check "creates several debian/ files (lm-sensors)"   multi_debian_creates.patch         debian
check "empty file has no header at all"              empty.patch                        invalid
check "-p0-style header without a/ or b/ prefix"      p0_style.patch                     invalid

if [ "$fail" -ne 0 ]; then
    echo "patch_class_test: FAILED"
    exit 1
fi
echo "patch_class_test: all assertions passed"
