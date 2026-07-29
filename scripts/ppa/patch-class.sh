# 判断一个补丁改的路径全在 debian/ 下、全在 debian/ 之外、还是两者都有。
#
# dpkg-source 的 "3.0 (quilt)" 格式里,debian/patches/* 只应用给上游代码;
# debian/ 目录本身以 debian.tar 里的最终内容打包。dpkg-source -b 重建校验
# 树时,会把 series 里列出的补丁整个重新应用一遍去跟当前工作树比较——如果
# 一个补丁既在 series 里、又真的改了 debian/ 下的文件,那处改动在工作树里
# 已经是最终态,重新应用等于第二次打,dpkg-source 会报 "Reversed (or
# previously applied) patch detected!"。
#
# 因此按补丁修改的路径分两类分别处理:
#   - 只改 debian/* → 应该直接焙进解包出的树,不进 series
#   - 只改 debian/* 之外 → 照常进 series,交给 builder 在构建时应用
#   - 两者都有 → 上面两条规则都套不上,报错交给人工拆分,不猜
#
# 用法(source 本文件,不要直接执行):
#   source scripts/ppa/patch-class.sh
#   patch_class <补丁文件>        # 打印 debian / upstream / mixed 到 stdout
#
# 判定依据:每条 "--- " 和 "+++ " 头去掉第一个路径分量(quilt refresh -p ab
# 产出的 a/、b/ 前缀)之后剩下的路径是否以 debian/ 开头。两条头都要看,不能
# 只看 "+++ ":对于删除文件的 hunk,真实路径在 "--- " 行,"+++ " 行只是字面量
# /dev/null——只看 "+++ " 会把删除 debian/ 下文件的补丁误判成 upstream,连带
# 把本该拦下的 mixed(删 debian/ 文件 + 改 upstream 文件)也放过。/dev/null
# 本身(来自新建或删除的那一侧)不代表任何路径,要跳过,不能去掉分量后当成
# "dev/null" 参与判断。

patch_class() {
    local patch="$1"
    local has_debian=0 has_upstream=0
    local line path
    while IFS= read -r line; do
        path="${line#[-+][-+][-+] }"
        path="${path%%$'\t'*}"   # 有些 diff 会在路径后带一个制表符+时间戳
        [ "$path" = "/dev/null" ] && continue   # 新建/删除那一侧,没有真实路径
        path="${path#*/}"        # 去掉第一个路径分量(a/ 或 b/)
        case "$path" in
            debian/*) has_debian=1 ;;
            *)        has_upstream=1 ;;
        esac
    done < <(grep -E '^(---|\+\+\+) ' "$patch")

    if [ "$has_debian" -eq 1 ] && [ "$has_upstream" -eq 1 ]; then
        echo mixed
    elif [ "$has_debian" -eq 1 ]; then
        echo debian
    else
        echo upstream
    fi
}
