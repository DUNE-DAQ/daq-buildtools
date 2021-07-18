
from colorama import Fore, Style
from inspect import currentframe, getframeinfo
import io
import os
import sh
import sys

DBT_AREA_FILE='dbt-settings'
UPS_PKGLIST="{}.sh".format(DBT_AREA_FILE)

def error(errmsg):
    timenow = io.StringIO()
    sh.date("+%D %T", _out=timenow)

    frameinfo = getframeinfo(currentframe().f_back)

    print("{}ERROR: [{}] [{}:{}]: {}{}".format(Fore.RED, timenow.getvalue().strip(), frameinfo.filename, frameinfo.lineno, errmsg, Style.RESET_ALL), file = sys.stderr)
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
    releases = io.StringIO()
    sh.find("-L", release_basepath, "-maxdepth", "2", "-name", UPS_PKGLIST, "-printf", "'%h '", _out=releases)

    for reldir in releases.getvalue().split("'"):
        reldir=reldir.strip()
        if reldir != "":
            print(" - {}".format(os.path.basename(reldir)))

def get_num_processors():
    nprocs=io.StringIO()
    sh.wc(sh.grep("-E", "processor\s*:\s*[0-9]+", "/proc/cpuinfo"), "-l", _out=nprocs)
    return nprocs.getvalue().strip()

def get_time(kind):

    stringio_obj = io.StringIO()

    if kind == "as_date":
        sh.date(_out=stringio_obj)        
    elif kind == "as_seconds_since_epoch":
        sh.date("+%s", _out=stringio_obj)
    else:
        assert(False, "Unknown argument passed to get_time")

    return stringio_obj.getvalue().strip()

