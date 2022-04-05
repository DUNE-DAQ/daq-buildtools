
import glob
from inspect import currentframe, getframeinfo
import os
import subprocess
import sys

exec(open(f'{os.environ["DBT_ROOT"]}/scripts/dbt_setup_constants.py').read())

def error(errmsg):
    timenow = subprocess.run(["date"], capture_output=True).stdout.decode("utf-8").strip()
    frameinfo = getframeinfo(currentframe().f_back)

    REDIFY="\033[91m"
    UNREDIFY="\033[0m"
    print("{}ERROR: [{}] [{}:{}]: {}{}".format(REDIFY, timenow, frameinfo.filename, frameinfo.lineno, errmsg, UNREDIFY), file = sys.stderr)
    sys.exit(1)

def find_work_area():
    return os.environ["DBT_AREA_ROOT"]

def list_releases(release_basepath):

    versions = []

    origdir=os.getcwd()
    os.chdir(f"{release_basepath}")
    for dirname in glob.glob(f"*"):
        versions.append(dirname)

    for version in sorted(versions):
        print(f" - {version}")

    os.chdir(origdir)
        
def get_time(kind):
    if kind == "as_date":
        dateargs=["date"]
    elif kind == "as_seconds_since_epoch":
        dateargs=["date", "+%s"]
    else:
        assert False, "Unknown argument passed to get_time"

    return subprocess.run(dateargs, capture_output=True).stdout.decode("utf-8").strip()
