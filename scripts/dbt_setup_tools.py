
import glob
from inspect import currentframe, getframeinfo
import os
import re
import subprocess
import sys
import datetime
import time
import shlex

exec(open(f'{os.environ["DBT_ROOT"]}/scripts/dbt_setup_constants.py').read())

def error(errmsg):
    timenow = get_time("as_date")
    frameinfo = getframeinfo(currentframe().f_back)

    REDIFY="\033[91m"
    UNREDIFY="\033[0m"
    print("{}ERROR: [{}] [{}:{}]: {}{}".format(REDIFY, timenow, frameinfo.filename, frameinfo.lineno, errmsg, UNREDIFY), file = sys.stderr)
    sys.exit(1)

def find_work_area():
    currdir=subprocess.check_output('pwd', shell=True).decode("utf-8").strip()
    while True:
        file_path = os.path.join(currdir, DBT_AREA_FILE)

        if os.path.exists(file_path):
            return currdir
        elif currdir != "":
            currdir="/".join(currdir.split("/")[:-1])
        else:
            return ""

def list_releases(release_basepath):

    versions = []
    base_release_regex_signifiers = ["^dunedaq-", "^NB", "B_", "^rc-", "^coredaq-"]

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

def run_command(cmd, cwd=None, check=True, warn=True,
                context=None, echo=True, shell=False, **kwargs):
    """
    Run a bash command, echo its output, and return the CompletedProcess.

    Args:
        cmd: Command as a string ("git clone repo") or list (["git", "clone", "repo"]).
            Strings are tokenized with shlex.split unless shell=True. Wrap interpolated
            values in f-strings using shlex.quote():
                run_command(f"du -sk {shlex.quote(path)}")
        cwd: Directory to run the command in. Defaults to the current directory.
        check: Raise RuntimeError if the command exits nonzero.
        warn: When check=False, print the failure message to stderr. Set warn=False when
            a nonzero exit is an expected result you handle yourself — e.g. `git diff
            --quiet` exits 1 to mean "dirty tree".
        context: Extra text prepended to error messages, describing what was attempted.
        echo: Print the command's stdout.
        shell: Run the command through /bin/sh rather than executing it directly.
            Required for shell syntax — pipes, redirects, globs, ~, $VAR, &&:
                run_command(f"spack find --loaded | grep {shlex.quote(path)} | wc -l",
                            shell=True)
            Caveats: a pipeline reports only the last command's exit status (prefix with
            "set -o pipefail; " to catch earlier failures), and metacharacters in
            interpolated values are interpreted, so never pass unsanitized input.
        **kwargs: Passed through to subprocess.run (timeout, env, input, ...)

    Returns:
        subprocess.CompletedProcess, with .stdout, .stderr, .returncode, .args.

    Raises:
        RuntimeError: if the command cannot be started, or exits nonzero and check=True.
    """
    if shell:
        argv = pretty = cmd if isinstance(cmd, str) else shlex.join(cmd)
    elif isinstance(cmd, str):
        argv, pretty = shlex.split(cmd), cmd
    else:
        argv, pretty = cmd, shlex.join(cmd)

    try:
        proc = subprocess.run(
            argv, cwd=cwd, capture_output=True, text=True, shell=shell, **kwargs,
        )
    except (OSError, subprocess.SubprocessError) as e:
        raise RuntimeError("\n".join(filter(None, [context, f"Could not run: {pretty}", str(e)]))) from e

    if echo and proc.stdout:
        print(proc.stdout, end="")

    if proc.returncode != 0:
        message = "\n".join(filter(None, [
            context,
            f"Command failed ({proc.returncode}): {pretty}",
            f"stdout:\n{proc.stdout}" if proc.stdout else "",
            f"stderr:\n{proc.stderr}" if proc.stderr else "",
        ]))
        if check:
            raise RuntimeError(message)
        if warn:
            print(message, file=sys.stderr)

    return proc

# This function is needed as part of daq-release Issue #500
# Its namesake bash counterpart can be found in dbt-setup-tools.sh

def get_target_package_name(release_dir):
    spec_files = glob.glob(f"{release_dir}/spec_*_log.txt")
    assert len(spec_files) == 1, f"Glob of {release_dir}/spec_*_log.txt didn't yield one and only one file"

    spec_file = spec_files[0]

    assert os.path.exists(spec_file)
    res = re.search(r".*/spec_([^_]+)_log.txt", spec_file)

    assert res
    return res.group(1)
