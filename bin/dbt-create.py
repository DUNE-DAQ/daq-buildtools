#!/usr/bin/env python
import sys
if sys.version_info[0] < 3:
    raise Exception("""Python 3 is required.
On systems with cvmfs, you can obtain python 3 by:
$ source /cvmfs/dunedaq.opensciencegrid.org/products/setup; setup python""")

import os
DBT_ROOT=os.environ["DBT_ROOT"]

exec(open('{}/scripts/dbt_create.py'.format(DBT_ROOT)).read())

