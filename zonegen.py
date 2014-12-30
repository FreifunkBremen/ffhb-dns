#! /usr/bin/env python

import sys
import json
import codecs
import re
from datetime import datetime

def str_to_domainlabel(s):
    label = re.sub("[^0-9a-zA-Z-]", "-", s)
    label = re.sub("-+", "-", label)
    label = re.sub("^-*", "", label)
    label = re.sub("-*$", "", label)

    if not re.match("^[a-zA-Z][a-zA-Z0-9-]{,61}[a-zA-Z0-9]$", label):
        raise RuntimeError("Not convertable to a domain label: %s" % s)

    return label

data = json.load(sys.stdin)

print """$TTL 1h
@       IN      SOA     ns.ffhb. liste.bremen.freifunk.net. (
        %s ; serial
        1h ; refresh
        30m ; retry
        2d ; expiration
        1h ; caching
        )

                NS      ns.ffhb.

""" % datetime.now().strftime("%Y%m%d%H%M")

for node in data.values():
    try:
        for address in node['network']['addresses']:
            if address.startswith("fe80:"):
                continue

            print "%-15s AAAA    %s" % (str_to_domainlabel(node['hostname']), address)
    except:
        pass
