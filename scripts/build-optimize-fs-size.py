#!/usr/bin/env python3

import argparse
import glob
import os
import shutil
import subprocess
import sys

DRY_RUN = False
def enable_dry_run(enabled):
    global DRY_RUN # pylint: disable=global-statement
    DRY_RUN = enabled

class FsRoot:
    def __init__(self, path):
        self.path = path

    def iter_fsroots(self):
        yield self.path
        dimgpath = os.path.join(self.path, 'var/lib/docker/overlay2')
        for layer in os.listdir(dimgpath):
            yield os.path.join(dimgpath, layer, 'diff')

    def collect_fsroot_size(self):
        cmd = ['du', '-sb', self.path]
        p = subprocess.run(cmd, text=True, check=False,
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        return int(p.stdout.split()[0])

    def _remove_root_paths(self, relpaths):
        for root in self.iter_fsroots():
            for relpath in relpaths:
                path = os.path.join(root, relpath)
                if os.path.isdir(path):
                    if DRY_RUN:
                        print(f'rmtree {path}')
                    else:
                        shutil.rmtree(path)

    def remove_docs(self):
        self._remove_root_paths([
            'usr/share/doc',
            'usr/share/doc-base',
            'usr/local/share/doc',
            'usr/local/share/doc-base',
        ])

    def remove_mans(self):
        self._remove_root_paths([
            'usr/share/man',
            'usr/local/share/man',
        ])

    def remove_licenses(self):
        self._remove_root_paths([
            'usr/share/common-licenses',
        ])

    def hardlink_under(self, path):
        # Link identical files that also share mode, owner and xattrs; mtime is ignored.
        # path may be a glob; all matches go to one call so files are linked across them.
        paths = sorted(glob.glob(os.path.join(self.path, path)))
        if not paths:
            raise FileNotFoundError(f'no match for {path} under {self.path}')
        cmd = ['hardlink', '--respect-xattrs', '--ignore-time']
        if DRY_RUN:
            cmd.append('--dry-run')
        subprocess.run(cmd + paths, check=True)

    def remove_platforms(self, filter_func):
        devpath = os.path.join(self.path, 'usr/share/sonic/device')
        for platform in os.listdir(devpath):
            if not filter_func(platform):
                path = os.path.join(devpath, platform)
                if DRY_RUN:
                    print(f'rmtree platform {path}')
                else:
                    shutil.rmtree(path)

    def remove_modules(self, modules):
        modpath = os.path.join(self.path, 'lib/modules')
        kversion = os.listdir(modpath)[0]
        kmodpath = os.path.join(modpath, kversion)
        for module in modules:
            path = os.path.join(kmodpath, module)
            if os.path.isdir(path):
                if DRY_RUN:
                    print(f'rmtree module {path}')
                else:
                    shutil.rmtree(path)

    def remove_firmwares(self, firmwares):
        fwpath = os.path.join(self.path, 'lib/firmware')
        for fw in firmwares:
            path = os.path.join(fwpath, fw)
            if os.path.isdir(path):
                if DRY_RUN:
                    print(f'rmtree firmware {path}')
                else:
                    shutil.rmtree(path)


    def specialize_aboot_image(self):
        fp = lambda p: '-' not in p or 'arista' in p or 'common' in p
        self.remove_platforms(fp)
        self.remove_modules([
           'kernel/drivers/gpu',
           'kernel/drivers/infiniband',
        ])
        self.remove_firmwares([
           'amdgpu',
           'i915',
           'mediatek',
           'nvidia',
           'radeon',
        ])

    def specialize_image(self, image_type):
        if image_type == 'aboot':
           self.specialize_aboot_image()

def parse_args(args):
    parser = argparse.ArgumentParser()
    parser.add_argument('fsroot',
        help="path to the fsroot build folder")
    parser.add_argument('-s', '--stats', action='store_true',
        help="show space statistics")
    parser.add_argument('--hardlinks', action='append',
        help="path where similar files need to be hardlinked")
    parser.add_argument('--remove-docs', action='store_true',
        help="remove documentation")
    parser.add_argument('--remove-licenses', action='store_true',
        help="remove license files")
    parser.add_argument('--remove-mans', action='store_true',
        help="remove manpages")
    parser.add_argument('--image-type', default=None,
        help="type of image being built")
    parser.add_argument('--dry-run', action='store_true',
        help="only display what would happen")
    return parser.parse_args(args)

def main(args):
    args = parse_args(args)

    enable_dry_run(args.dry_run)

    fs = FsRoot(args.fsroot)
    if args.stats:
        begin = fs.collect_fsroot_size()
        print(f'fsroot size is {begin} bytes')

    if args.remove_docs:
        fs.remove_docs()

    if args.remove_mans:
        fs.remove_mans()

    if args.remove_licenses:
        fs.remove_licenses()

    if args.image_type:
        fs.specialize_image(args.image_type)

    for path in args.hardlinks:
        fs.hardlink_under(path)

    if args.stats:
        end = fs.collect_fsroot_size()
        pct = 100 - end / begin * 100
        print(f'fsroot reduced to {end} from {begin} {pct:.2f}')

    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
