#! /usr/bin/python

import sys
import commands
import json
# import datetime
from datetime import datetime

command = "task +reminder +PENDING rc.verbose=nothing rc.json.array=no export" 
DATEFORMAT = '%Y%m%dT%H%M%SZ'

for task in commands.getoutput(command).split("\n"):
    data = json.loads(task)
    date=datetime.strptime(data['due'], DATEFORMAT)
    print u"{0}\n{1}\n{2}\n{3}".format(data['id'],data['description'],"{0}/{1}/{2}".format(date.day,date.month,date.year),"FALSE").encode('utf-8').strip()

sys.exit (0)


