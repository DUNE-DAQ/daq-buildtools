#!/bin/env python
#
# Download all the repos that are not archived in the DUNE-DAQ organization
# Usage: python dbt-clone.py or ./dbt-clone.py
#
import urllib.request
import json
import subprocess
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--archived', action='store_true', help='Also clone archived repos')
args = parser.parse_args()

CNTX='orgs'
NAME='DUNE-DAQ'
PAGE='1'
# I'm not sure if per_page caps at 100
res = urllib.request.urlopen(f'https://api.github.com/{CNTX}/{NAME}/repos?page={PAGE}&per_page=500')
js = json.load(res)
ls = []
for elem in js:
    url = elem['ssh_url']
    if args.archived or not elem['archived']:
        res = subprocess.Popen(f'git clone {url}'.split())
        ls.append(res)
for process in ls:
    process.wait()
print('Done cloning')
