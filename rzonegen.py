#! /usr/bin/env python3

import sys
import json
import re
import ipaddress
from datetime import datetime

def str_to_domainlabel(s):
    label = re.sub("[^0-9a-zA-Z-]", "-", s)
    label = re.sub("-+", "-", label)
    label = re.sub("^-*", "", label)
    label = re.sub("-*$", "", label)

    if not re.match("^[a-zA-Z][a-zA-Z0-9-]{,61}[a-zA-Z0-9]$", label):
        raise RuntimeError("Not convertable to a domain label: %s" % s)
    return label

def ipv6_addr_to_rdns(addr):
    return ".".join(reversed(addr.exploded.replace(':', ''))) + ".ip6.arpa."

data = json.load(sys.stdin)
domain = sys.argv[1]
if not domain.startswith("."):
    domain = "." + domain

if not domain.endswith("."):
    domain = domain + "."

print("""$TTL 1h
@       IN      SOA     vpn03.bremen.freifunk.net. noc.bremen.freifunk.net. (
        %s ; serial
        1h ; refresh
        30m ; retry
        2d ; expiration
        1h ; caching
        )

                NS      vpn02.bremen.freifunk.net.
                NS      vpn03.bremen.freifunk.net.
""" % datetime.now().strftime("%Y%m%d%H%M"))

for node in data.values():
    try:
        for address in node['network']['addresses']:
            try:
                address = ipaddress.IPv6Address(address)
            except ValueError:
                continue

            if address.is_link_local or address.is_private:
                continue

            rdns = ipv6_addr_to_rdns(address)

            if rdns.endswith(domain):
                print("%s PTR %s.nodes.ffhb.de." % (rdns[0:-len(domain)], str_to_domainlabel(node['hostname'])))
    except (KeyError, RuntimeError):
        pass
