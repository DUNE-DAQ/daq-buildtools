#!/usr/bin/env python3

import os
import sys
import yaml
import argparse
import subprocess


def get_field(fman, fkey):
    try:
        fvalue = fman[fkey]
    except KeyError:
        print("Field {} does not exist in the manifest file!".format(fkey))
    return fvalue


def parse_manifest_file(fname):
    if not os.path.exists(fname):
        print("Error: -- Manifest file {} does not exist".format(fname))
        exit(20)
    fman = ""
    with open(fname, 'r') as stream:
        try:
            fman = yaml.safe_load(stream)
        except yaml.YAMLError as exc:
            print(exc)
    return fman


def merge_dict(y1, y2):
    for key, value in y2.items():
        if key in y1:
            if value is None:
                continue
            elif type(value) is dict:
                merge_dict(y1[key], y2[key])
            elif type(value) is list:
                y1[key].extend(y2[key])
            else:
                y1[key] = y2[key]
        else:
            y1[key] = y2[key]
    return


def merge_dict_list(listd):
    if listd is None:
        return
    tags = list(listd[0].keys())
    mlistd = [[] for x in tags]
    for i in listd:
        if i[tags[0]] not in mlistd[0]:
            for j in range(len(tags)):
                mlistd[j].append(i[tags[j]])
        else:
            idx = mlistd[0].index(i[tags[0]])
            for j in range(1, len(tags)):
                mlistd[j][idx] = i[tags[j]]
    listd = [ {tags[k]:mlistd[k][i] for k in range(len(tags))} \
        for i in range(len(mlistd[0])) ]
    return listd


def merge_manifest_files(fnames):
    """Merge dictionaries in the list, elements with higher index take
    precedence; fnames looks like [running, develop, user]"""
    fman = {}
    for i in fnames:
        merge_dict(fman, parse_manifest_file(i))
    for i in ["external_deps", "src_pkgs", "prebuilt_pkgs"]:
        fman[i] = merge_dict_list(fman[i])

    return fman


def cmd_setup_product_path(fman):
    setup_string=""
    for i in fman["product_paths"]:
        setup_string += ". {}/setup\n".format(i)
        setup_string += """if [[ "$?" != 0 ]]; then
  echo "Executing \". {}/setup\" resulted in a nonzero return value; returning..."
  return 10
fi\n""".format(i)
    print(setup_string)
    return setup_string


def cmd_products_setup(fman, fsection):
    """return line seperated UPS setup commands to be used in 'eval' in bash
    scripts"""
    setup_string = 'setup_returns=""\n'
    for i in fman[fsection]:
        if i["variant"] is not None:
            setup_string += "setup {} {} -q {}\n".format(
            i["name"], i["version"], i["variant"])
        else:
            setup_string += "setup {} -v {}\n".format(
            i["name"], i["version"])
        setup_string += 'setup_returns=$setup_returns"$? "\n'
    setup_string += """if ! [[ "\$setup_returns" =~ [1-9] ]]; then
  echo "All setup calls on the packages returned 0, indicative of success"
else
  echo "At least one of the required packages this script attempted to set up didn't set up correctly; returning..." >&2
  return 1
fi
"""
    print(setup_string)
    return setup_string


def check_output(cmd):
    irun = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    out = irun.communicate()
    rc = irun.returncode
    if rc != 0:
        print('Error: command "{}" has exit non-zero exit status, please check!'.format(cmd))
        print('Output from the commnd: {}'.format(out))
        exit(10)
    return out


def run_git_checkout(fman, srcdir):
    git_repos = fman["src_pkgs"]
    for i in git_repos:
        icmd = "mkdir -p {} && cd {} && git clone {} && cd {} && git checkout {} && cd ..;".format(
                srcdir, srcdir, i["repo"], i["name"], i["tag"])
        iout = check_output(icmd)
        print("Info[Git Checkout]: -- {}".format(iout))
    return


###MAIN FUNCTION#########

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
            prog='parse-manifest.py',
            description="Parse DUNE DAQ release manifest files.",
            epilog="Questions and comments to dingpf@fnal.gov")
    parser.add_argument('--setup-product-path', action='store_true',
            help='''Generate bash commands for setting up UPS product path;''')
    parser.add_argument('--setup-external', action='store_true',
            help='''generate line separated bash commands of setting up UPS
            products for external dependencies;''')
    parser.add_argument('--setup-prebuilt', action='store_true',
            help='''generate line separated bash commands of setting up ups
            products for prebuilt daq packages;''')
    parser.add_argument('--git-checkout', action='store_true',
            help='''Run git clone and checkout commands for DAQ source packages
            from GitHub repos;''')
    parser.add_argument('-s', '--src-dir', default='./sourcecode',
            help="source code directory;")
    parser.add_argument('-r', '--release', default='develop',
            help="set the DAQ release to use;")
    parser.add_argument('-p', '--path-to-manifest', default='./daq-release',
            help="set the path to DAQ release manifest files;")
    parser.add_argument('-u', '--users-manifest',
            default=None,
            help="set the path to user's manifest files;")

    args = parser.parse_args()

    if args.release == "develop":
        release = "develop"
    else:
        release = args.release.replace('.', '-')
    release_manifest = "{}/release_{}.yaml".format(
            args.path_to_manifest, release)
    user_manifest = args.users_manifest


    fnames = [release_manifest]
    if user_manifest is not None:
        fnames.append(user_manifest)
    fman = merge_manifest_files(fnames)
    #print(fman)
    #print(yaml.dump(fman, default_flow_style=False, sort_keys=False))

    if args.setup_product_path:
       cmd_setup_product_path(fman)
    if args.setup_external:
        cmd_products_setup(fman, "external_deps")
    if args.setup_prebuilt:
        cmd_products_setup(fman, "prebuilt_pkgs")
    if args.git_checkout:
        run_git_checkout(fman, args.src_dir)
