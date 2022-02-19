
from inspect import currentframe, getframeinfo
import io
import os
import subprocess
from subprocess import Popen
import sys

exec(open(f'{os.environ["DBT_ROOT"]}/scripts/dbt_setup_constants.py').read())
UPS_PKGLIST="{}.sh".format(DBT_AREA_FILE)

def error(errmsg):
    proc = Popen(["date", "+%D %T"], stdout=subprocess.PIPE)
    timenow = proc.stdout.readlines()[0].decode("utf-8").strip()

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
 
def list_releases(release_basepath):

    proc = Popen(["find", "-L", release_basepath, "-maxdepth", "2", "-name", UPS_PKGLIST, "-printf", "%h\n"], \
                 stdout=subprocess.PIPE)

    for reldir in proc.stdout.readlines():
        reldir=reldir.decode("utf-8").strip()
        if reldir != "":
            print(" - {}".format(os.path.basename(reldir)))

def get_num_processors():
    proc = Popen(["grep", "-E", "processor\s*:\s*[0-9]+", "/proc/cpuinfo"], stdout=subprocess.PIPE)
    nprocs = len(proc.stdout.readlines())
    return str(nprocs)

def get_time(kind):
    if kind == "as_date":
        dateargs = ["date"]
    elif kind == "as_seconds_since_epoch":
        dateargs = ["date", "+%s"]
    else:
        assert False, "Unknown argument passed to get_time"

    return Popen(dateargs, stdout=subprocess.PIPE).stdout.readlines()[0].decode("utf-8").strip()
