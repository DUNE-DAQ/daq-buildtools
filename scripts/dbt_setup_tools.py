
import glob
from inspect import currentframe, getframeinfo
import io
import os
import re
import subprocess
import sys

exec(open(f'{os.environ["DBT_ROOT"]}/scripts/dbt_setup_constants.py').read())
UPS_PKGLIST="{}.sh".format(DBT_AREA_FILE)

def error(errmsg):
    timenow = subprocess.run(["date"], capture_output=True).stdout.decode("utf-8").strip()
    frameinfo = getframeinfo(currentframe().f_back)

    REDIFY="\033[91m"
    UNREDIFY="\033[0m"
    print("{}ERROR: [{}] [{}:{}]: {}{}".format(REDIFY, timenow, frameinfo.filename, frameinfo.lineno, errmsg, UNREDIFY), file = sys.stderr)
    sys.exit(1)

def find_work_area():
    currdir=os.getcwd()

    while True:
        if os.path.exists("{}/{}".format(currdir, DBT_AREA_FILE)):
            return currdir
        elif currdir != "":
            currdir="/".join(currdir.split("/")[:-1])
        else:
            return ""

def list_releases(release_basepath, use_spack):

    if not use_spack:
        for filename in sorted(glob.glob(f"{release_basepath}/*")):
            if os.path.exists(f"{os.path.realpath(filename)}/{UPS_PKGLIST}"):
                print(f" - {os.path.basename(filename)}")
    else:
        versions = []
        basedir=f"{SPACK_BASEPATH}/opt/spack/linux-scientific7-sandybridge"
        if not os.path.exists(basedir):
            error(f"Unable to find expected directory {basedir}; exiting...")

        for dirname in glob.glob(f"{basedir}/gcc-*/dune-daqpackages-*"):
            res = re.search(r".*dune-daqpackages-(.*)-[a-z0-9]{32}.*", dirname)
            assert res
            versions.append(res.group(1))

        for version in sorted(versions):
            print(version)

def get_time(kind):
    if kind == "as_date":
        dateargs=["date"]
    elif kind == "as_seconds_since_epoch":
        dateargs=["date", "+%s"]
    else:
        assert False, "Unknown argument passed to get_time"

    return subprocess.run(dateargs, capture_output=True).stdout.decode("utf-8").strip()
