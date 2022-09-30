import os
DBT_ROOT=os.environ["DBT_ROOT"]
exec(open(f'{DBT_ROOT}/scripts/dbt_setup_constants.py').read())

import argparse
import pathlib
from shutil import copy
import subprocess
import sys
from time import sleep


sys.path.append(f'{DBT_ROOT}/scripts')

from dbt_setup_tools import error, get_time, list_releases

PY_PKGLIST="pyvenv_requirements.txt"
DAQ_BUILDORDER_PKGLIST="dbt-build-order.cmake"

usage_blurb=f"""

Usage
-----

To create a new DUNE DAQ development area:

    {os.path.basename(__file__)} [-n/--nightly] [-b/--base-release <base release type>]  [-r/--release-path <path to release area>] [-i/--install-pyvenv] <dunedaq-release> <target directory>

To list the available DUNE DAQ releases:

    {os.path.basename(__file__)} [-n/--nightly] [-b/--base-release <base release type>] [-r/--release-path <path to release area>] -l/--list 

Arguments and options:

    dunedaq release: the release the new work area will be based on (e.g. dunedaq-v2.8.0, N22-09-29, etc.)
    target directory: the name of the work area dbt-create will set up for you  
    -b/--base-release: base release type, can be one of [frozen, nightly, candidate]. Default is frozen.
    -n/--nightly: switch from frozen to nightly releases, shortcut for \"-b nightly\"
    -l/--list: show the list of available releases 
    -r/--release-path: is the path to the release archive (defaults to 
                       {PROD_BASEPATH} (frozen)
                       {NIGHTLY_BASEPATH} (nightly)
                       {CANDIDATE_RELEASE_BASEPATH} (candidate))
    -i/--install-pyvenv: rather than cloning the python virtual environment, 
                         pip install it off of the pyvenv_requirements.txt 
                         file in the release's directory on cvmfs

See https://dune-daq-sw.readthedocs.io/en/latest/packages/daq-buildtools for more

"""


parser = argparse.ArgumentParser(usage=usage_blurb)
parser.add_argument("-n", "--nightly", action="store_true", help=argparse.SUPPRESS)
parser.add_argument("-b", "--base-release", choices=['frozen', 'nightly', 'candidate'], default='frozen', help=argparse.SUPPRESS)
parser.add_argument("-r", "--release-path", action='store', dest='release_path', help=argparse.SUPPRESS)
parser.add_argument("-l", "--list", action="store_true", dest='_list', help=argparse.SUPPRESS)
parser.add_argument("-i", "--install-pyvenv", action="store_true", dest='install_pyvenv', help=argparse.SUPPRESS)
parser.add_argument("-p", "--pyvenv-requirements", action='store', dest='pyvenv_requirements', help=argparse.SUPPRESS)
parser.add_argument("release_tag", nargs='?', help=argparse.SUPPRESS)
parser.add_argument("workarea_dir", nargs='?', help=argparse.SUPPRESS)

args = parser.parse_args()

if args.pyvenv_requirements and not args.install_pyvenv:
    error("""
You supplied the name of a Python requirements file but therefore also need
to add --install-pyvenv as an argument
""")

if args.release_path:
    RELEASE_BASEPATH=args.release_path
else:
    if args.nightly:
        args.base_release = 'nightly'
    if args.base_release == 'frozen':
        RELEASE_BASEPATH=PROD_BASEPATH
    if args.base_release == 'nightly':
        RELEASE_BASEPATH=NIGHTLY_BASEPATH
    if args.base_release == 'candidate':
        RELEASE_BASEPATH=CANDIDATE_RELEASE_BASEPATH

if args._list:
    list_releases(RELEASE_BASEPATH)
    sys.exit(0)
elif not args.release_tag or not args.workarea_dir:
    error("Need to supply a release tag and a new work area directory. Run '{} -h' for more information.".format(os.path.basename(__file__)))

RELEASE_PATH=os.path.realpath(f"{RELEASE_BASEPATH}/{args.release_tag}")
RELEASE=RELEASE_PATH.rstrip("/").split("/")[-1]
if RELEASE != args.release_tag:
    print(f"Release \"{args.release_tag}\" requested; interpreting this as release \"{RELEASE}\"")

if not os.path.exists(RELEASE_PATH):
    error(f"""
Release path
\"{RELEASE_PATH}\"
does not exist. Note that you need to pass \"-n\" for a nightly build or \"-b candidate\"
for a candidate release build. Exiting...""")

TARGETDIR=args.workarea_dir
if os.path.exists(TARGETDIR):
    error(f"""Desired work area directory
\"{TARGETDIR}\" already exists; exiting...""")

if "DBT_WORKAREA_ENV_SCRIPT_SOURCED" in os.environ:
    error("""
It appears you're trying to run this script from an environment
where another development area's been set up.  You'll want to run this
from a clean shell. Exiting...
"""
)

starttime_d=get_time("as_date")
starttime_s=get_time("as_seconds_since_epoch")

try:
    pathlib.Path(TARGETDIR).mkdir(parents=True)
except PermissionError:
    error(f"You don't have permission to create {TARGETDIR} from {os.getcwd()}. Exiting...")

os.chdir(TARGETDIR)
TARGETDIR=os.getcwd() # Get full path

BUILDDIR=f"{TARGETDIR}/build"
LOGDIR=f"{TARGETDIR}/log"
SRCDIR=f"{TARGETDIR}/sourcecode"

for workareadir in [BUILDDIR, LOGDIR, SRCDIR]:
    os.mkdir(workareadir)

os.chdir(SRCDIR)

for dbtfile in [f"{DBT_ROOT}/configs/CMakeLists.txt", \
                f"{DBT_ROOT}/configs/CMakeGraphVizOptions.cmake", \
                f"{RELEASE_PATH}/{DAQ_BUILDORDER_PKGLIST}"
                ]:
    copy(dbtfile, SRCDIR)

os.symlink(f"{DBT_ROOT}/env.sh", f"{TARGETDIR}/dbt-env.sh")

# Set these so the dbt-clone-pyvenv.sh and dbt-create-pyvenv.sh scripts get info they need
os.environ["SPACK_RELEASE"] = f"{RELEASE}"
os.environ["SPACK_RELEASES_DIR"] = f"{RELEASE_BASEPATH}"

workarea_constants_file_contents = \
    f"""export SPACK_RELEASE="{os.environ["SPACK_RELEASE"]}"
export SPACK_RELEASES_DIR="{os.environ["SPACK_RELEASES_DIR"]}"
export DBT_ROOT_WHEN_CREATED="{os.environ["DBT_ROOT"]}"
"""

with open(f'{TARGETDIR}/dbt-workarea-constants.sh', "w") as outf:
    outf.write(workarea_constants_file_contents)

print("Setting up the Python subsystem.")
if not args.install_pyvenv:
    cmd = f"{DBT_ROOT}/scripts/dbt-clone-pyvenv.sh {RELEASE_PATH}/{DBT_VENV} 2>&1"
else:
    print("Please be patient, this should take O(1 minute)...")
    if not args.pyvenv_requirements:
        cmd = f"{DBT_ROOT}/scripts/dbt-create-pyvenv.sh {RELEASE_PATH}/{PY_PKGLIST} 2>&1"
    else:
        if not os.path.exists(args.pyvenv_requirements):
            error(f"""
Requested Python requirements file \"{args.pyvenv_requirements}\" not found. 
Please note you need to provide its absolute path. Exiting...
""")
        cmd = f"{DBT_ROOT}/scripts/dbt-create-pyvenv.sh {args.pyvenv_requirements} 2>&1"

res = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE)

while True:
    output = res.stdout.readline()
    if res.poll() is not None:
        break
    if output:
        print(output.rstrip().decode("utf-8"))
    res.poll()

if res.returncode != 0:
    error(f"There was a problem running \"{cmd}\" (return value {res.returncode}); exiting...")

endtime_d=get_time("as_date")
endtime_s=get_time("as_seconds_since_epoch")

print(f"""
Total time to run {__file__}: {int(endtime_s) - int(starttime_s)} seconds
Start time: {starttime_d}
End time:   {endtime_d}

See https://dune-daq-sw.readthedocs.io/en/latest/packages/daq-buildtools for build instructions

Script completed successfully

""")

