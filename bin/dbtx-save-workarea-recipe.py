#!/usr/bin/env python3

import os
import yaml
import subprocess
import click

class CustomError(click.ClickException):
    def format_message(self):
        return f"🚨 ERROR: {self.message}"

def run_git_cmd(repo_path,args,quiet_fail=False):
    return subprocess.check_output(['git', '-C', repo_path] + args,
                                   stderr=subprocess.DEVNULL if quiet_fail else None).decode().strip()

def get_dunedaq_release_type(release_name):
    if 'rc' in release_name:
        return 'candidate'
    elif release_name.startswith('N'):
        return 'nightly'
    else:
        return 'frozen' #use frozen for now, for better backwards compatibility
        #return 'static'

def validate_git_commit(repo_path, commit, repo_name):

    # 1. Check for uncommitted changes
    status = run_git_cmd(repo_path,['status', '--porcelain'])
    if status:
        click.echo(f"🚨 ERROR: Repository '{repo_name}' has uncommitted changes! "
                   "Commit them before re-running.",
                   err=True)
        return False

    # 2. Check if commit is reachable from a remote branch or tag
    branches = run_git_cmd(repo_path,['branch', '-r', '--contains', commit])
    if not any('origin/' in line for line in branches.splitlines()):
        click.echo(f"🚨 ERROR: Commit {commit[:7]} in repo '{repo_name}' is not pushed to origin. "
                   "Push before re-running.",
                   err=True)
        return False

    #if neither of those, commit is ok
    return True

def validate_git_ref(repo_path, ref, repo_name):

    # Check if ref (branch or tag) exists on origin
    # Note that this should only produce a warning if not available
    ref_exists = False

    branch_check = run_git_cmd(repo_path,['ls-remote', '--heads', 'origin', ref])
    if branch_check:
        ref_exists = True

    if not ref_exists:
        tag_check = run_git_cmd(repo_path,['ls-remote', '--tags', 'origin', ref])
        if tag_check:
            ref_exists = True

    if not ref_exists:
        click.echo(f"⚠️  WARNING: Ref '{ref}' in repo '{repo_name}' does not exist on origin."
                    "Push reference, or only commit hashes will work.")

    return ref_exists

def get_repo_info(repo_path):

    #get the repo name, and the url
    name = os.path.basename(repo_path)
    #url = f'https://github.com/DUNE-DAQ/{name}.git'
    #url = run_git_cmd(['config', '--get', 'remote.origin.url'])

    #now, get the repo ref. Call it 'NONE' if unknown.
    try:
        # Try to get branch name
        ref = run_git_cmd(repo_path,['symbolic-ref', '--short', 'HEAD'],quiet_fail=True)
    except subprocess.CalledProcessError:
        # If in detached HEAD, get current tag or commit hash
        try:
            ref = run_git_cmd(repo_path,['describe', '--tags'],quiet_fail=True)
        except subprocess.CalledProcessError:
            ref = None

    commit = run_git_cmd(repo_path,['rev-parse', 'HEAD'])

    ref_valid = validate_git_ref(repo_path,ref,name) if ref else False
    commit_valid = validate_git_commit(repo_path,commit,name)

    return {
        'name': name,
        #'url': url,
        'ref': ref,
        'ref_valid': ref_valid,
        'commit': commit,
        'commit_valid': commit_valid
    }

@click.command()
@click.argument('recipe_name')
@click.option('--require-valid-refs',is_flag=True,
              help='Require all refs are valid (default False)')
def save_workarea_recipe(recipe_name,require_valid_refs):
    """Generate a DAQ workarea setup recipe based on the current source tree.

    RECIPE_NAME is the base name for the output YAML file.
    """

    yaml_filename = f"{recipe_name}.yaml"
    daq_release = os.environ.get("DUNE_DAQ_BASE_RELEASE")

    if not daq_release:
        raise CustomError("DUNE_DAQ_BASE_RELEASE not set in environment! "
                          "Setup dunedaq before running this script.")

    sourcecode_dir = os.path.join(os.environ.get("DBT_AREA_ROOT"), "sourcecode")

    repos = []
    all_commits_valid = True
    all_refs_valid = True

    for entry in os.listdir(sourcecode_dir):
        repo_path = os.path.join(sourcecode_dir, entry)
        if os.path.isdir(repo_path) and os.path.isdir(os.path.join(repo_path, '.git')):
            repos.append(get_repo_info(repo_path))
            if not repos[-1]['commit_valid']: all_commits_valid = False
            if not repos[-1]['ref_valid']: all_refs_valid = False

    #check that all commits are ok, and optionally that all refs are ok
    if not all_commits_valid:
        raise CustomError('Not all commits are valid. Check errors and rerun.')

    if require_valid_refs and not all_refs_valid:
        raise CustomError('Not all refs are valid, and you have requested they are. '
                          'Check errors/warnings and rerun.')

    config = {
        'recipe_name': recipe_name,
        'daq_release': daq_release,
        'daq_release_type': get_dunedaq_release_type(daq_release),
        'repos': repos
    }

    with open(yaml_filename, 'w') as f:
        yaml.dump(config, f, sort_keys=False)

    click.echo(f"Wrote setup recipe to {yaml_filename}")

if __name__ == '__main__':
    save_workarea_recipe()
