#! /usr/bin/env bash
# 2014, Moritz Kaspar Rudert (mortzu) <mr@planetcyborg.de>.
# All rights reserved.

# Redistribution and use in source and binary forms, with or without modification, are
# permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this list of
#   conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice, this list
#   of conditions and the following disclaimer in the documentation and/or other materials
#   provided with the distribution.
#
# * The names of its contributors may not be used to endorse or promote products derived
#   from this software without specific prior written permission.
#
# * Feel free to send Club Mate to support the work.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS
# OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS
# AND CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# PID file
PID_FILE="/run/ffhb-update-dns.pid"

# getting workingdir of scripts
WORK_DIR="$(dirname $(readlink -nf $0))"

# set safe path
PATH="${WORK_DIR}:/sbin:/usr/sbin:/bin:/usr/bin"

# define variable to count loops
declare -i NUM=0

# tmp file
TMP_FILE="$(mktemp)"

# if creation of tmp file failed
# exit
if [ -z "$TMP_FILE" ]; then
  exit 1
fi

# names of zones
ZONEFILE=/var/cache/bind/ffhb.nodes.zone
RZONEFILE=/var/cache/bind/arpa.ip6.f.d.2.f.5.1.1.9.0.f.2.c.zone

# write run file
if [ -f "$PID_FILE" ]; then
  echo "Script already running!" >&2
  exit 1
else
  touch "$PID_FILE"
fi

# loop until data received
while true; do
  # increment counter
  NUM=$(($NUM+1))

  # get data from alfred
  # but limit the time
  timeout -s KILL 30s alfred-json -z -r 158 >"$TMP_FILE" 2>/dev/null

  # on success leave loop
  if [ $? -eq 0 ]; then
    break
  fi

  # if the 240th run has reached kill script
  if [ $NUM -gt 240 ]; then
    # remove tmp file
    rm -f "$TMP_FILE"

    # exit with error code
    exit 1
  fi

  # sleep to be safe CPU load don't getting higher
  sleep 1
done

# generate forward zone
if zonegen.py <"$TMP_FILE" >"${ZONEFILE}.new"; then
  mv "${ZONEFILE}.new" "${ZONEFILE}"
fi

# generate reverse zone
if rzonegen.py 0.0.0.0.c.2.f.0.9.1.1.5.f.2.d.f.ip6.arpa <"$TMP_FILE" >"${RZONEFILE}.new"; then
  mv "${RZONEFILE}.new" "${RZONEFILE}"
fi

# reload nameserver
rndc reload >/dev/null

# remove tmp file
rm -f "$TMP_FILE"

# remove PID file
rm -f "$PID_FILE"
