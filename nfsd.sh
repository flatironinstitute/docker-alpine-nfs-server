#!/bin/bash

# Make sure we react to these signals by running stop() when we see them - for clean shutdown
# And then exiting
trap "stop; exit 0;" SIGTERM SIGINT

stop()
{
  # We're here because we've seen SIGTERM, likely via a Docker stop command or similar
  # Let's shutdown cleanly
  echo "SIGTERM caught, terminating NFS process(es)..."
  /usr/sbin/exportfs -uav
  /usr/sbin/rpc.nfsd 0
  pid1=`pidof rpc.nfsd`
  pid2=`pidof rpc.mountd`
  # For IPv6 bug:
  pid3=`pidof rpcbind`
  kill -TERM $pid1 $pid2 $pid3 > /dev/null 2>&1
  echo "Terminated."
  exit
}

if [ -z "${EXPORTS_MOUNTED}" ]; then
  echo "Building /etc/exports file..."
  /usr/bin/exports.sh || exit 1
# EXPORTS_MOUNTED is set, ensure a file is mounted
elif [ -f /etc/exports ]; then
  echo "Skipping creation of /etc/exports, user has set EXPORTS_MOUNTED and mounted a file at /etc/exports"
else
  echo "EXPORTS_MOUNTED is set but no file found at /etc/exports. Exiting..."
  exit 1
fi

# Partially set 'unofficial Bash Strict Mode' as described here: http://redsymbol.net/articles/unofficial-bash-strict-mode/
# We don't set -e because the pidof command returns an exit code of 1 when the specified process is not found
# We expect this at times and don't want the script to be terminated when it occurs
set -uo pipefail
IFS=$'\n\t'

echo "Displaying /etc/exports contents:"
cat /etc/exports
echo ""

# Normally only required if v3 will be used
# But currently enabled to overcome an NFS bug around opening an IPv6 socket
echo "Starting rpcbind..."
/sbin/rpcbind -w
echo "Displaying rpcbind status..."
/sbin/rpcinfo

# Only required if v3 will be used
# /usr/sbin/rpc.idmapd
# /usr/sbin/rpc.gssd -v
# /usr/sbin/rpc.statd

echo "Starting NFS in the background..."
/usr/sbin/rpc.nfsd --debug 8 --no-udp --no-nfs-version 3
echo "Exporting File System..."
if /usr/sbin/exportfs -rv; then
  /usr/sbin/exportfs
else
  echo "Export validation failed, exiting..."
  exit 1
fi

# Set thread count after startup
if [ -n "${NFS_THREADS:-}" ]; then
  echo "${NFS_THREADS}" > /proc/fs/nfsd/threads 2>/dev/null
fi
echo "NFS running with $(cat /proc/fs/nfsd/threads) worker threads"

echo "Starting Mountd in the background..."
/usr/sbin/rpc.mountd -F --debug all --no-udp --no-nfs-version 3
# --exports-file /etc/exports
