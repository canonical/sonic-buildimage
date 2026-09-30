set -u
W=~/vmtest/gv; cd $W; rm -f zboot-*.log
docker run --rm -v $W:/w debian:bookworm bash -c '
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq --no-install-recommends build-essential bison flex gawk python3 xz-utils wget ca-certificates pkg-config libdevmapper-dev >/dev/null 2>&1 || { echo DEPS_FAIL; exit 1; }
cd /tmp
for v in 2.06 2.12; do
  ( wget -q https://ftp.gnu.org/gnu/grub/grub-$v.tar.xz && tar xf grub-$v.tar.xz && cd grub-$v && \
    [ -f grub-core/extra_deps.lst ] || echo "depends bli part_gpt" > grub-core/extra_deps.lst; \
    ./configure --with-platform=efi --target=aarch64 --disable-werror --prefix=/opt/g$v > /tmp/cfg-$v.log 2>&1 && make -j32 > /tmp/mk-$v.log 2>&1 && \
    ./grub-mkstandalone -d grub-core -O arm64-efi -o /w/vanilla-$v.efi --modules="part_gpt fat gzio search search_label linux echo configfile" "boot/grub/grub.cfg=/w/test.cfg" && echo "vanilla-$v built" ) || { echo "vanilla-$v FAIL"; tail -5 /tmp/mk-$v.log /tmp/cfg-$v.log 2>/dev/null; }
done'
ls -la vanilla-*.efi 2>&1
. /tmp/gvfuncs.sh
echo "######## vanilla boot matrix"
for efi in vanilla-*.efi; do for f in zboot.efi image image.gz; do run $efi $f & done; done; wait
