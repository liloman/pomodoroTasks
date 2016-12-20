#! /usr/bin/python
#Show a reminder grid when it is on the timeout screen to remind the user
# "the reminder tasks". They are the kind of task that are recurrent (birthdays,...) or the
# kind of task that must be done in a certain date must be reminded just sometime in advance.
# Useful for day to day tiny tasks,
# like "call Mary to 6PM" or remind me the next month with 10 days in advance that 
# I have to look into something.
# Works with https://github.com/liloman/warriors/blob/master/ptask.sh
# ./ptask.sh reminder to add a new one ;)


import sys
import commands
import json
# import datetime
from datetime import datetime

command = "task +reminder +PENDING rc.verbose=nothing rc.json.array=no export" 
DATEFORMAT = '%Y%m%dT%H%M%SZ'

for task in commands.getoutput(command).split("\n"):
    try:
        data = json.loads(task)
        date=datetime.strptime(data['due'], DATEFORMAT)
        print u"{0}\n{1}\n{2}\n{3}".format(data['id'],data['description'],"{0}/{1}/{2}".format(date.day,date.month,date.year),"FALSE").encode('utf-8').strip()
    except:
        sys.exit (0)


sys.exit (0)


