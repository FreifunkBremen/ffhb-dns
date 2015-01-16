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

# variable to check changes
declare -i CHANGED=0

# PID file
RUN_FILE="$HOME/.var/run/ffhb-dns"

# destination zonefile directory
DEST_DIR="$HOME/zones"

# getting workingdir of scripts
WORK_DIR="$(dirname $(readlink -nf $0))"

# set safe path
PATH=/usr/local/bin:/sbin:/usr/sbin:/bin:/usr/bin

function on_exit() {
  # remove tmp files
  if [ -n "$RUN_FILE" ]; then
    rm -f "$RUN_FILE"
  fi
}

trap on_exit EXIT SIGTERM SIGINT

# write run file
if [ -f "$RUN_FILE" ]; then
  echo 'Script already running!' >&2
  exit 1
else
  mkdir -p "$(dirname $RUN_FILE)"
  touch "$RUN_FILE"
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
  FILE_NAME="$(basename $FILE)"

  # construct origin
  ORIGIN="$(basename "${FILE/.zone/}")"

  cp "$FILE" "$TMP_FILE"

  # if zone already exists
  if [ -f "${DEST_DIR}/${FILE_NAME}" ]; then
    # save old serial number
    OLD_SERIAL="$(grep -Eho "20[0-1][0-9]{7}" "${DEST_DIR}/${FILE_NAME}")"

    # strip serial from old and new files
    # diff is easier without different serial numbers
    TMP_FILE_OLD="$(mktemp)"
    TMP_FILE_NEW="$(mktemp)"
    sed -e '/20[0-1][0-9]\{7\}/d' "${DEST_DIR}/${FILE_NAME}" >"$TMP_FILE_OLD"
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

  # changed variable
  CHANGED=1

  # update serial
  if [ -n "$OLD_SERIAL" ]; then
    NEW_SERIAL=$(($OLD_SERIAL + 1))
  else
    NEW_SERIAL=$(date +'%Y%m%d%H')
  fi
  sed -e 's/20[0-1][0-9]\{7\}/'${NEW_SERIAL}'/g' -i "$TMP_FILE"

  # move the file to real place
  mv "$TMP_FILE" "${DEST_DIR}/${FILE_NAME}"

  # fix permissions
  chmod 0644 "${DEST_DIR}/${FILE_NAME}"
done

if [ $CHANGED -ne 0 ]; then
  planetcyborg-dns-reload
fi
