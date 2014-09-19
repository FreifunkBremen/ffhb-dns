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

    if not re.match("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", label):
        raise RuntimeError("Not convertable to a domain label: %s" % s)
    return label

def ipv6_addr_to_rdns(addr):
    rdns = ""
    counter = 4

    for char in reversed(addr):
        if char == ':':
            rdns += counter * '0.'
            counter = 4
        else:
            rdns += char + '.'
            counter -= 1

    rdns += 'ip6.arpa.'
    return rdns

data = json.load(sys.stdin)
domain = sys.argv[1]
if not domain.startswith("."):
    domain = "." + domain

if not domain.endswith("."):
    domain = domain + "."

print("""$TTL 1h
@       IN      SOA     ns.ffhb. liste.bremen.freifunk.net. (
        %s ; serial
        1h ; refresh
        30m ; retry
        2d ; expiration
        1h ; caching
        )

@		NS      ns01.ffhb.
""" % datetime.now().strftime("%Y%m%d%H%M"))

for node in data.values():
    try:
        for address in node['network']['addresses']:
            if address.startswith("fe80:"):
                continue

            rdns = ipv6_addr_to_rdns(address)

            if rdns.endswith(domain):
                print "%s PTR %s.nodes.ffhb." % (ipv6_addr_to_rdns(address)[0:-len(domain)], str_to_domainlabel(node['hostname']))
    except:
        pass
