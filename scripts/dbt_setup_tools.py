
import glob
from inspect import currentframe, getframeinfo
import os
import re
import subprocess
import sys
import datetime
import time

exec(open(f'{os.environ["DBT_ROOT"]}/scripts/dbt_setup_constants.py').read())

def error(errmsg):
    timenow = get_time("as_date")
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

    versions = []
    base_release_regex_signifiers = ["^dunedaq-", "^NB", "^rc-", "^coredaq-"]

    origdir=os.getcwd()
    os.chdir(f"{release_basepath}")
    for dirname in glob.glob(f"*"):
        if os.path.isfile(dirname):
            continue

        is_base_release = False
        for regex in base_release_regex_signifiers:
            if re.search(regex, dirname):
                is_base_release = True

        if is_base_release:
            continue
            
        versions.append(dirname)

    for version in sorted(versions):
        print(f" - {version}")

    os.chdir(origdir)

def get_time(kind):
    if kind == "as_date":
        timenow = datetime.datetime.now().astimezone().strftime("%a %b %-d %H:%M:%S %Z %Y")
    elif kind == "as_seconds_since_epoch":
        timenow = int(time.time())
    else:
        assert False, "Unknown argument passed to get_time"

    return timenow

def run_command(cmd):

    res = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE)

    while True:
        output = res.stdout.readline()
        if output:
            print(output.rstrip().decode("utf-8"))
        if res.poll() is not None:
            break

    if res.returncode != 0:
        error(f"There was a problem running \"{cmd}\" (return value {res.returncode}); exiting...")
