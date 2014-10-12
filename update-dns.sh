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

# TMP file
TMP_CONFIG_FILE="$(mktemp)"

# PID file
RUN_FILE='/run/update-dns-ffhb.run'

# destination zonefile directory
DEST_DIR='/var/cache/bind'

DEST_CONFIG_FILE="${DEST_DIR}/ffhb-zones.conf"

# getting workingdir of scripts
WORK_DIR="$(dirname $(readlink -nf $0))"

# set safe path
PATH=/sbin:/usr/sbin:/bin:/usr/bin

# several sites to get IP address
GET_MY_IP=( "http://getip.planetcyb.org" "http://whatismyip.oceanus.ro" "http://www.whatismyip.us" "http://whatismyip.everdot.org" "http://www.whatismyip.ca" "http://whatismyip.com.au" "http://www.whatismyip.nl" "http://www.whatismyip.ro" "http://www.whatismyip.se" )

EXTERNAL_IPV4_ADDR=''
EXTERNAL_IPV6_ADDR="$(perl -MNetAddr::IP -MNet::Address::IP::Local -e "print NetAddr::IP->new6(Net::Address::IP::Local->public_ipv6)->short()" | tr '[A-Z]' '[a-z]')"
EXTERNAL_IPV6_NETWORK="$(perl -MNetAddr::IP -e "print NetAddr::IP->new6('${EXTERNAL_IPV6_ADDR}/64')->network->short()" | tr '[A-Z]' '[a-z]' | sed -e 's/::$//g')"

function on_exit() {
  # remove tmp files
  for FILE in "$RUN_FILE" "$TMP_CONFIG_FILE"; do
    if [ -n "$FILE" ]; then
      rm -f "$FILE"
    fi
  done
}

trap on_exit EXIT SIGTERM SIGINT

# write run file
if [ -f "$RUN_FILE" ]; then
  echo 'Script already running!' >&2
  exit 1
else
  touch "$RUN_FILE"
fi

# get IPv4 address
for URL in "${GET_MY_IP[@]}"; do
  EXTERNAL_IPV4_ADDR="$(curl -m4 -4 -s -- ${URL} | grep -Eo "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -n1)"

  if [ -n "$EXTERNAL_IPV4_ADDR" ]; then
    break
  fi
done

# print error if determining of IP addresses failed
if [ -z "$EXTERNAL_IPV4_ADDR" -o -z "$EXTERNAL_IPV6_ADDR" ]; then
  echo 'Determining of IP address failed!' >&2
  exit 1
fi

# refresh git repository
git --work-tree="${WORK_DIR}" --git-dir="${WORK_DIR}/.git" pull -q --rebase=false origin master

# loop over zones
for FILE in ${WORK_DIR}/data/*; do
  # tmp file
  TMP_FILE="$(mktemp)"

  # reset some variables
  OLD_SERIAL=''
  NEW_SERIAL=''

  # construct realname
  REAL_NAME="$(basename $FILE)"

  # construct origin
  ORIGIN="$(basename "${FILE/.zone/}")"

  # build zone name from filename
  declare -a DOMAIN_PARTS
  IFS='.' read -a DOMAIN_PARTS <<< "$ORIGIN"
  DOMAIN=''
  for (( idx=${#DOMAIN_PARTS[@]}-1 ; idx>=0 ; idx-- )) ; do
    [ -n "$DOMAIN" ] && DOMAIN="$DOMAIN.${DOMAIN_PARTS[idx]}" || DOMAIN="${DOMAIN_PARTS[idx]}"
  done

  # replace the first dash with a slash
  # for RDNS zones smaller than /24
  if [ $(grep -o '-' <<<"$DOMAIN" | wc -l) -gt 1 ]; then
    DOMAIN="$(sed -e 's#-#/#' <<< $DOMAIN)"
  fi

  # write new config entry
  cat >> "$TMP_CONFIG_FILE" <<EOF
zone "$DOMAIN" {
  type master;
  file "${DEST_DIR}/${REAL_NAME}";
  allow-query { any; };
  notify yes;
};
EOF

  # replace placeholder with real ip adresses
  sed -e "s/___EXTERNAL-IPV4-ADDR___/${EXTERNAL_IPV4_ADDR}/g" -e "s/___EXTERNAL-IPV6-ADDR___/${EXTERNAL_IPV6_ADDR}/g" -e "s/___EXTERNAL-IPV6-NETWORK___/${EXTERNAL_IPV6_NETWORK}/g" "$FILE" >"$TMP_FILE"

  # if zone already exists
  if [ -f "${DEST_DIR}/${REAL_NAME}" ]; then
    # save old serial number
    OLD_SERIAL="$(grep -Eho "20[0-1][0-9]{7}" "${DEST_DIR}/${REAL_NAME}")"

    # strip serial from old and new files
    # diff is easier without different serial numbers
    TMP_FILE_OLD="$(mktemp)"
    TMP_FILE_NEW="$(mktemp)"
    sed -e '/20[0-1][0-9]\{7\}/d' "${DEST_DIR}/${REAL_NAME}" >"$TMP_FILE_OLD"
    sed -e '/20[0-1][0-9]\{7\}/d' "$TMP_FILE" >"$TMP_FILE_NEW"

    # check if update is necessary
    if diff -q "$TMP_FILE_OLD" "$TMP_FILE_NEW" >/dev/null 2>&1; then
      # if zones are identically
      # remove tmp files
      for FILE in "$TMP_FILE" "$TMP_FILE_OLD" "$TMP_FILE_NEW"; do
        if [ -n "$FILE" ]; then
          rm -f "$FILE"
        fi
      done
      continue
    fi
  fi

  # check if zone is valid
  if ! named-checkzone "$DOMAIN" "$TMP_FILE" >/dev/null 2>&1; then
    echo "$FILE is not valid!" >&2
    for FILE in "$TMP_FILE" "$TMP_FILE_OLD" "$TMP_FILE_NEW"; do
      if [ -n "$FILE" ]; then
        rm -f "$FILE"
      fi
    done
    continue
  fi

  # update serial
  if [ -n "$OLD_SERIAL" ]; then
    NEW_SERIAL=$(($OLD_SERIAL + 1))
  else
    NEW_SERIAL=$(date +'%Y%m%d%H')
  fi
  sed -e 's/20[0-1][0-9]\{7\}/'${NEW_SERIAL}'/g' -i "$TMP_FILE"

  # move the file to real place
  mv "$TMP_FILE" "${DEST_DIR}/${REAL_NAME}"

  # fix permissions
  chmod 0644 "${DEST_DIR}/${REAL_NAME}"
done

if [ ! -f "$DEST_CONFIG_FILE" ] || ( [ -n "$(cat $TMP_CONFIG_FILE)" ] && ! diff -q "$TMP_CONFIG_FILE" "$DEST_CONFIG_FILE" >/dev/null 2>&1 ); then
  mv "$TMP_CONFIG_FILE" "$DEST_CONFIG_FILE"
  chmod 0644 "$DEST_CONFIG_FILE"
fi

# reload nameserver
rndc reload >/dev/null
