import os
DBT_ROOT=os.environ["DBT_ROOT"]
exec(open(f'{DBT_ROOT}/scripts/dbt_setup_constants.py').read())

import sys
sys.path.append(f'{PROD_BASEPATH}/dunedaq-v2.8.2/dbt-pyvenv/lib/python3.8/site-packages')

import argparse
import io
import pathlib
import sh
from shutil import copy
import subprocess
from time import sleep


sys.path.append(f'{DBT_ROOT}/scripts')

from dbt_setup_tools import error, get_time, list_releases

EMPTY_DIR_CHECK=True

PY_PKGLIST="pyvenv_requirements.txt"
DAQ_BUILDORDER_PKGLIST="dbt-build-order.cmake"

usage_blurb=f"""

Usage
-----

To create a new DUNE DAQ development area:
      
    {os.path.basename(__file__)} [-n/--nightly] [-c/--clone-pyvenv] [-r/--release-path <path to release area>] <dunedaq-release> <target directory>

To list the available DUNE DAQ releases:

    {os.path.basename(__file__)} [-n/--nightly] -l/--list [-r/--release-path <path to release area>]

Arguments and options:

    dunedaq-release: is the name of the release the new work area will be based on (e.g. dunedaq-v2.8.0)
    -n/--nightly: switch from frozen to nightly releases
    -l/--list: show the list of available releases
    -c/--clone-pyvenv: cloning the dbt-pyvenv from cvmfs instead of installing from scratch    
    -r/--release-path: is the path to the release archive (defaults to either {PROD_BASEPATH} (frozen) or {NIGHTLY_BASEPATH} (nightly))

See https://dune-daq-sw.readthedocs.io/en/latest/packages/daq-buildtools for more

""" 


parser = argparse.ArgumentParser(usage=usage_blurb)
parser.add_argument("-n", "--nightly", action="store_true", help=argparse.SUPPRESS)
parser.add_argument("-c", "--clone", action="store_true", help=argparse.SUPPRESS)
parser.add_argument("-r", "--release-path", action='store', dest='release_path', help=argparse.SUPPRESS)
parser.add_argument("-l", "--list", action="store_true", dest='_list', help=argparse.SUPPRESS)
parser.add_argument("release_tag", nargs='?', help=argparse.SUPPRESS)
parser.add_argument("workarea_dir", nargs='?', help=argparse.SUPPRESS)

args = parser.parse_args()

if args.release_path:
    RELEASE_BASEPATH=args.release_path
elif not args.nightly:
    RELEASE_BASEPATH=PROD_BASEPATH
else:
    RELEASE_BASEPATH=NIGHTLY_BASEPATH

if args._list:
    list_releases(RELEASE_BASEPATH)
    sys.exit(0)
elif not args.release_tag or not args.workarea_dir:
    error("Wrong number of arguments. Run '{} -h' for more information.".format(os.path.basename(__file__)))

RELEASE=args.release_tag

stringio_obj1 = io.StringIO()
sh.realpath("-m", f"{RELEASE_BASEPATH}/{RELEASE}", _out=stringio_obj1)
RELEASE_PATH=stringio_obj1.getvalue().strip()

TARGETDIR=args.workarea_dir

if not os.path.exists(RELEASE_PATH):
    error(f"Release path '{RELEASE_PATH}' does not exist. Note that you need to pass \"-n\" for a nightly build. Exiting...")

if "DBT_WORKAREA_ENV_SCRIPT_SOURCED" in os.environ:
    error("""
It appears you're trying to run this script from an environment                                             
where another development area's been set up.  You'll want to run this                                      
from a clean shell. Exiting... 
"""
)
    
starttime_d=get_time("as_date")
starttime_s=get_time("as_seconds_since_epoch")

if not os.path.exists(TARGETDIR):
    pathlib.Path(TARGETDIR).mkdir(parents=True, exist_ok=True)

os.chdir(TARGETDIR)
TARGETDIR=os.getcwd() # Get full path

BUILDDIR=f"{TARGETDIR}/build"
LOGDIR=f"{TARGETDIR}/log"
SRCDIR=f"{TARGETDIR}/sourcecode"

if EMPTY_DIR_CHECK and os.listdir("."):
    error(f"""
There appear to be files in {TARGETDIR} besides this script                                                  
(run "ls -a1 {TARGETDIR}" to see this); this script should only be run in a clean                                  directory. Exiting...  
""")
elif not EMPTY_DIR_CHECK:
    print("""
WARNING: The check for whether any files besides this script exist in                                       
its directory has been switched off. This may mean assumptions the                                          
script makes are violated, resulting in undesired behavior.    
    """, file=sys.stderr)
    sleep(5)

for workareadir in [BUILDDIR, LOGDIR, SRCDIR]:
    os.mkdir(workareadir)

os.chdir(SRCDIR)

for dbtfile in [f"{DBT_ROOT}/configs/CMakeLists.txt", \
                f"{DBT_ROOT}/configs/CMakeGraphVizOptions.cmake", \
                f"{RELEASE_PATH}/{DAQ_BUILDORDER_PKGLIST}"
                ]:
    copy(dbtfile, SRCDIR)

copy(f"{RELEASE_PATH}/{UPS_PKGLIST}", f"{TARGETDIR}/{DBT_AREA_FILE}")

os.symlink(f"{DBT_ROOT}/env.sh", f"{TARGETDIR}/dbt-env.sh")

print("Setting up the Python subsystem.") 

if args.clone:
    cmd = f"{DBT_ROOT}/scripts/dbt-clone-pyvenv.sh {RELEASE_PATH}/{DBT_VENV}"
else:
    print("Please be patient, this should take O(1 minute)...")
    cmd = f"{DBT_ROOT}/scripts/dbt-create-pyvenv.sh {RELEASE_PATH}/{PY_PKGLIST}"

res = subprocess.run( cmd.split() )
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

