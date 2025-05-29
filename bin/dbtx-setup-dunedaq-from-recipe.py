#!/usr/bin/env python3

import os
DBT_ROOT=os.environ["DBT_ROOT"]
exec(open(f'{DBT_ROOT}/scripts/dbt_setup_constants.py').read())

import argparse
from datetime import datetime
import subprocess
import sys
import tempfile
import urllib.request
import yaml

sys.path.append(f'{DBT_ROOT}/scripts')
from dbt_setup_tools import error

parser = argparse.ArgumentParser()
parser.add_argument('--use-ref', action='store_true',
                    help='Use the ref (branch or tag) instead of the exact commit hash')
parser.add_argument('--build', action='store_true',
                    help='Also build the local area after creating it.')
parser.add_argument('--use-ssh-repos', action='store_true',
                    help='Use ssh repo sources, instead of https (default)')
parser.add_argument('--workarea-name', action='store', dest='workarea_name',
                    help='Optional name for workarea to create (default: testarea_<recipe_name>_<timestamp>)')
parser.add_argument('recipe_source', nargs='?',
                    help='Name of a recipe file create via dbt-generate-dunedaq-setup-recipe.py')

args = parser.parse_args()

if not args.recipe_source:
    error("You need to supply the name of a recipe\n file to this script; rerun with \"-h\" for further details")

def setup_dunedaq_from_recipe(recipe_source, use_ref, build, use_ssh_repos, workarea_name):
    """Set up a DAQ workarea based on a saved configuration file or a URL"""

    is_url = recipe_source.startswith("http://") or recipe_source.startswith("https://")
    
    if is_url:
        print(f"Downloading config from: {recipe_source}")
        with urllib.request.urlopen(recipe_source) as response:
            content = response.read()
        tmp_file = tempfile.NamedTemporaryFile(delete=False)
        with open(tmp_file.name, "wb") as f:
            f.write(content)
        recipe_file = tmp_file.name
    else:
        recipe_file = os.path.abspath(recipe_source)
        if not os.path.exists(recipe_file):
            error(f"Config file {recipe_file} not found.")
        
    with open(recipe_file) as f:
        recipe = yaml.safe_load(f)

    daq_release = recipe['daq_release']
    daq_release_type = recipe['daq_release_type']
    recipe_name = recipe['recipe_name']
    repos = recipe['repos']

    #before doing anything, first check that the commits or refs were valid at creation
    all_commits_valid = True
    all_refs_valid = True
    for repo in repos:
        name = repo['name']
        ref = repo['ref']
        ref_valid = repo['ref_valid']
        commit = repo['commit']
        commit_valid = repo['commit_valid']

        if not commit_valid:
            error(f'🚨 ERROR: commit {commit} in repo {name} not valid. Check with recipe creator.')
            all_commits_valid = False
        if not ref_valid and use_ref:
            error(f'🚨 ERROR: ref {ref} in repo {name} not valid. Check with recipe creator.')
            all_refs_valid = False

    if not all_commits_valid:
        error('Not all commits are valid. Check errors and rerun.')
    if not all_refs_valid and use_ref:
        error('Not all refs are valid and you have requested to use them. Check errors and rerun, or rerun without "--use-ref" option.')

    #now create a workarea
    timestamp = datetime.now().strftime('%d%b_%H%M')
    workarea_name = workarea_name or f"testarea_{recipe_name}_{timestamp}"

    print(f"Creating workarea '{workarea_name}' with release '{daq_release}'...")

    subprocess.run(['bash', '-c', f'''
        dbt-create -b {daq_release_type} {daq_release} {workarea_name}
    '''], check=True, executable='/bin/bash')

    workarea_path = os.path.abspath(workarea_name)
    
    sourcecode_path = os.path.join(workarea_path, "sourcecode")
    os.chdir(sourcecode_path)

    #now loop over the repos in the recipe, clone and checkout what's needed
    for repo in repos:
        name = repo['name']
        url = f'git@github.com:DUNE-DAQ/{name}.git' if use_ssh_repos else f'https://github.com/DUNE-DAQ/{name}.git'
        ref = repo['ref']
        commit = repo['commit']

        print(f"\nCloning {name} from {url}...")
        subprocess.run(['git', 'clone', url, name], check=True)

        repo_path = os.path.join(sourcecode_path, name)
        os.chdir(repo_path)

        #fetch everything
        subprocess.run(['git', 'fetch', '--all', '--tags'],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        resolved=False

        # Always check if the ref still points to the same commit

        # Try to resolve ref via origin/<ref> (for branches), then <ref> for tags
        for ref_candidate in [f'origin/{ref}', ref]:
            try:
                ref_commit = subprocess.check_output(['git', 'rev-list', '-n', '1', ref_candidate],
                                                     stderr=subprocess.DEVNULL).decode().strip()
                resolved = True
                break
            except subprocess.CalledProcessError:
                continue
            if resolved:
                if ref_commit != commit:
                    print(f"⚠️ WARNING: ref '{ref}' now points to a different commit than recorded")
                    print(f"   current: {ref_commit}")
                    print(f"   saved:   {commit}")
            else:
                print(f"⚠️  WARNING: could not resolve ref '{ref}' to check commit hash")

        # Checkout based on selected mode
        if use_ref:
            if not resolved:
                error(f'Unable to resolve {ref} in repo {name} and you have requested to use it. Check errors, or rerun without "--use-ref" option.')
            print(f"  Checking out ref: {ref}")
            subprocess.run(['git', 'checkout', ref], check=True)
        else:
            print(f"  Checking out commit: {commit}")
            subprocess.run(['git', 'checkout', commit], check=True)

        os.chdir(sourcecode_path)

    os.chdir(workarea_path)  # Back to workarea root

    print(f"\n ✅ Workarea '{workarea_path}' set up successfully.")

    if build:
        print("\nSetting up environment and building...")
        subprocess.run(['bash', '-c', f'''
            cd {workarea_path} &&
            source env.sh &&
            dbt-build -j 12 &&
            dbt-workarea-env
        '''], check=True, executable='/bin/bash')

        print(f"\n ✅ Workarea '{workarea_path}' built up successfully.")

setup_dunedaq_from_recipe(args.recipe_source, args.use_ref, args.build, args.use_ssh_repos, args.workarea_name)
