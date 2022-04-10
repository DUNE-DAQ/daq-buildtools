#!/usr/bin/env python
import sys

if not (sys.version_info[0] == 3 and sys.version_info[1] == 8 and sys.version_info[2] == 3):
    raise Exception("""Python 3.8.3 is required. On systems with cvmfs, you can obtain Python 3.8.3 by executing the following:

    source /cvmfs/dunedaq.opensciencegrid.org/spack-externals/spack-0.17.1/share/spack/setup-env.sh 
    spack load python@3.8.3%gcc@8.2.0""")

import os
DBT_ROOT=os.environ["DBT_ROOT"]

exec(open('{}/scripts/dbt_create.py'.format(DBT_ROOT)).read())

