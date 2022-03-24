#!/usr/bin/env python
import sys
if sys.version_info[0] < 3:
    if "--spack" not in sys.argv:
        raise Exception("""Python 3 is required.
    On systems with cvmfs, you can obtain python 3 by:
    $ source /cvmfs/dunedaq.opensciencegrid.org/products/setup; setup python""")
    else:
        raise Exception("""Python 3 is required. On systems with cvmfs, you can obtain Python 3 by executing the following:

        source /cvmfs/dunedaq-development.opensciencegrid.org/sandbox/spack/spack/share/spack/setup-env.sh 
        spack load python@3.8.3%gcc@8.2.0""")

import os
DBT_ROOT=os.environ["DBT_ROOT"]

exec(open('{}/scripts/dbt_create.py'.format(DBT_ROOT)).read())

