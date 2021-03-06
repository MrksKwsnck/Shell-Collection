#!/usr/bin/env bash
#
# Description:	Testing for SSDs whether TRIM function is set up correctly and 
#		working properly. See the given URL for further information.
# URL:		https://wiki.ubuntuusers.de/SSD/TRIM/Testen/
# Author:	Markus Kwaśnicki
#
# Known issues: Not working reliably with LVM partition scheme


################################################################################
#                                  Functions                                   #
################################################################################

function usage () {
  printf 'Usage: %s <SSD_DEVICE> <DIR_PATH>\n' $PROGRAM_NAME
  printf 'Example: %s /dev/sda /\n' $PROGRAM_NAME
} >&2

function eval_rc () {
  if [ $? -ne 0 ]; then
    printf 'External program "%s" exited with return code %d!\n' $2 $1 >&2
    exit $1
  fi
}

function clear_cache () {
  # Clear cache to make sure all data is written.
  echo 1 | sudo tee /proc/sys/vm/drop_caches
  sync
}


################################################################################
#                                Preconditions                                 #
################################################################################

PROGRAM_NAME=$(basename $0)
DEVICE_PATH=$1
TEST_DIRECTORY=$2	# Which resides on the SSD.

# Script must be executed with root privileges!
if [ "$(whoami)" != 'root' ]; then
  >&2 echo "You ain't root!"
  exit -1
fi

# Insufficient arguments!
if [ -z "$DEVICE_PATH" -o -z "$TEST_DIRECTORY" ]; then
  usage
  exit -2
fi


################################################################################
#                                     Main                                     #
################################################################################

# Determining SSD features.
FEATURE_LIST=$(hdparm -I $DEVICE_PATH | grep --ignore-case TRIM)
eval_rc $? hdparm
printf "TRIM Features:\n$FEATURE_LIST\n\n"


# Determining SSD type:

SSD_TYPE=	# Not defined

if echo "$FEATURE_LIST" | grep --quiet --ignore-case 'read data'; then
  # Is it type 1!
  SSD_TYPE=1
elif echo "$FEATURE_LIST" | grep --quiet --ignore-case 'read ZEROs'; then
  # Is it type 2!
  SSD_TYPE=2
else
  # It is type 3!
  SSD_TYPE=3
fi

printf "SSD Type: "

case $SSD_TYPE in
  2)  printf "%s\n\n" $SSD_TYPE
      ;;
  *)  printf "%s\n" $SSD_TYPE
      printf 'Test for TRIM of this SSD Type not yet implemented!\n'
      ;;
esac


# Testing the Kernel functionality for SSD type 2 only.

# Creating test file.
TEST_FILE="$TEST_DIRECTORY/trim.test"
printf 'Creating TRIM test file "%s"... ' "$TEST_FILE"
yes | dd iflag=fullblock bs=1M count=1 of="$TEST_FILE" 2> /dev/null
printf "done.\n"
clear_cache

# Determining test file position by its fragmentation in the file system. 
# Example output:
# Filesystem type is: ef53
# File size of /trim.test is 1048576 (256 blocks of 4096 bytes)
#  ext:     logical_offset:        physical_offset: length:   expected: flags:
#    0:        0..     255:     660224..    660479:    256:             eof
# /trim.test: 1 extent found
FILEFRAG=$(filefrag -s -v "$TEST_FILE")
echo "$FILEFRAG"
LINE=$(echo "$FILEFRAG" | sed -n 2p)	# 2nd line
BLOCKSIZE=$(expr "$LINE" : \
  '^.*([0-9]\+\s\+blocks\s\+of\s\+\([0-9]\+\)\s\+bytes).*$')	# Block size
LINE=$(echo "$FILEFRAG" | sed -n 4p)	# 4th line
OFFSET=$(echo "$LINE" | tr --squeeze-repeats ' ' '\t' | cut --fields=5 | \
  cut -d'.' -f1)	# Physical offset
LENGTH=$(echo "$LINE" | tr --squeeze-repeats ' ' '\t' | cut --fields=7 | \
  cut -d':' -f1)	# Count of blocks
DEVICE=$(df "$TEST_FILE" | sed -n 2p | cut -d' ' -f1)

# Read test file from file system before TRIMming.
DUMP_BEFORE=$(dd bs=$BLOCKSIZE skip=$OFFSET count=$LENGTH if=$DEVICE 2> /dev/null | hexdump -C)
echo "$DUMP_BEFORE"

# Delete test file...
rm "$TEST_FILE"
clear_cache

# Now trim all file systems!
/sbin/fstrim --all

# Read test file from file system after TRIMming.
DUMP_AFTER=$(dd bs=$BLOCKSIZE skip=$OFFSET count=$LENGTH if=$DEVICE 2> /dev/null | hexdump -C)
echo "$DUMP_AFTER"

# Evaluate: If the first hexdump is equal to the second hexdump, probably TRIM 
# is not working. The two dumps must differ!
if [ "$DUMP_BEFORE" = "$DUMP_AFTER" ]; then
  printf "\nTRIM is probably NOT working!\n"
  exit -3
fi
printf "\nTRIM seems to work fine.\n"
exit 0
