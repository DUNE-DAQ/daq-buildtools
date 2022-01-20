#!/usr/bin/env python
import sys
if sys.version_info[0] < 3:
    raise Exception("Python 3 is required. If you have access to cvmfs, run this ... first.")

import os
DBT_ROOT=os.environ["DBT_ROOT"]
exec(open('{}/scripts/dbt_create.py'.format(DBT_ROOT)).read())
