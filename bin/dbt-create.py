#!/usr/bin/env python3
import sys

if not (sys.version_info[0] == 3 and sys.version_info[1] >= 6):
    raise Exception("""Python > 3.6.0 is required. On systems with cvmfs, you can obtain Python 3.8.3 by executing the following:

    source `realpath /cvmfs/dunedaq.opensciencegrid.org/spack-externals/spack-installation/share/spack/setup-env.sh`
    spack load python@3.8.3%gcc@8.2.0""")

import os
DBT_ROOT=os.environ["DBT_ROOT"]

exec(open('{}/scripts/dbt_create.py'.format(DBT_ROOT)).read())

