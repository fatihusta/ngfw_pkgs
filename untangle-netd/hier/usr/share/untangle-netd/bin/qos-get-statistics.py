#!/usr/bin/env python
from parse import *
from subprocess import *
import json

# Get QoS statistics from the output of qos-service.py status command

#Parse patterns for qos-service.py status output
firstLine='interface: {} class {} {} {} rate {} ceil {} burst {} cburst {}'
secondLine=' Sent {:d} bytes {:d} pkt (dropped {:d}, overlimits {:d} requeues {:d}) '
thirdLine=' rate {} {} backlog {} {} requeues {:d} '
fourthLine= ' lended: {:d} borrowed: {:d} giants: {:d}'
lastLine=' tokens: {} ctokens:{}'
priorityParser='parent {} leaf {} prio {:d}'

indexMap={1:firstLine, 2:secondLine, 3:thirdLine, 4:fourthLine, 5:lastLine}

priorityQueueToName = { '10:': '0 - Default','11:': '1 - Very High','12:': '2 - High', '13:':'3 - Medium','14:':'4 - Low','15:':'5 - Limited','16:':'6 - Limited More','17:':'7 - Limited Severely' }

output = []
proc = Popen('/usr/share/untangle-netd/bin/qos-service.py status', stdout=PIPE, shell=True)
count = 1
entry = {}
skipEntry=False

for line in proc.stdout:
    if count <= 5:
        res=parse(indexMap[count],line)
        parsed = res.fixed
        if count == 1:
            entry['interface_name']=parsed[0]
            entry['burst']=parsed[len(parsed)-2]
            if 'prio' in parsed[3]:
                skipEntry=False
                prioParse = parse(priorityParser, parsed[3])
                val=prioParse.fixed
                entry['priority']=priorityQueueToName[val[1]]
            if parsed[3]=='root':
                skipEntry=True
        if count == 2:
            entry['sent']=str(parsed[0]) + ' bytes'
        if count == 3:
            entry['rate']=parsed[0]
        if count == 5:
            entry['tokens']=int(parsed[0])
            entry['ctokens']=int(parsed[1])
        count+=1
    else:
        if not skipEntry:
            output.append(dict(entry))
        entry.clear()
        count=1
        continue
newlist = sorted(output, key=lambda k: k['priority'])
print json.dumps(newlist)