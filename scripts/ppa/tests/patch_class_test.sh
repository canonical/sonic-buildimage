#!/bin/bash
# patch_class() 自测：用临时目录里手写的最小合法 unified diff 片段，覆盖
# scripts/ppa/patch-class.sh 分类的每一种输入形状,不依赖任何真实包的补丁。
#
# 这份测试本身是自包含的（*_test.sh 后缀，见 run-tests.sh 里的说明），跟
# test-build-source.sh 那种要传包名参数的测试不是一回事。
set -euo pipefail

cd "$(dirname "$0")/../../.."
source scripts/ppa/patch-class.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0

# 只改 debian/ 下的文件 → debian
cat > "$tmp/only_debian.patch" <<'EOF'
--- a/debian/rules
+++ b/debian/rules
@@ -1 +1 @@
-old
+new
EOF

# 只改 debian/ 之外的文件 → upstream
cat > "$tmp/only_upstream.patch" <<'EOF'
--- a/src/foo.c
+++ b/src/foo.c
@@ -1 +1 @@
-old
+new
EOF

# 一个改 debian/,一个改 upstream → mixed
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

# 新建 debian/ 下的文件（--- /dev/null）→ debian
cat > "$tmp/create_debian.patch" <<'EOF'
--- /dev/null
+++ b/debian/newfile
@@ -0,0 +1 @@
+new content
EOF

# 删除 debian/ 下的文件（+++ /dev/null，真实路径在 --- 行）→ debian
cat > "$tmp/delete_debian.patch" <<'EOF'
--- a/debian/oldfile
+++ /dev/null
@@ -1 +0,0 @@
-old content
EOF

# 删除一个 debian/ 文件,同时改一个 upstream 文件 → mixed
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

# 一个补丁里新建多个 debian/ 下的文件（lm-sensors 那种形状）→ debian
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

if [ "$fail" -ne 0 ]; then
    echo "patch_class_test: FAILED"
    exit 1
fi
echo "patch_class_test: all assertions passed"
