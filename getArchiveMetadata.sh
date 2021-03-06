#!/bin/bash
#######################################################################################
#
# This script walks you through the steps needed to navigate (via REST) the file 
# metadata in an archive.  Just edit the DEFAULT_* values near the top 
# of this script.
#
# # Copyright (c) 2016 Code42, Inc.
# Permission is hereby granted, free of charge, to any person obtaining a copy 
# of this software and associated documentation files (the "Software"), to deal 
# in the Software without restriction, including without limitation the rights 
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell 
# copies of the Software, and to permit persons to whom the Software is 
# furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in all 
# copies or substantial portions of the Software.
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
# SOFTWARE.
#
#######################################################################################

DEFAULT_CREDS="admin:admin"
#DEFAULT_MASTER_HTTP=https://proe-master.acme.com:4285
DEFAULT_MASTER_HTTP=https://proe-master.crashplan.com:7285
DEFAULT_GUID=570477308691873793
DEFAULT_DEST_GUID=73

# Choose one of several space-separated values
# arg1: prompt text that continues to be displayed until one of the values is chosen
# arg2: space-separated values
# arg3: optional default value to be used only when nothing is entered
# The result is that CHOICE is populated with entered value
function chooseOne {
        prompt="$1"
        list="$2"
        default="$3"
        CHOICE=
        [[ -n $default ]] && prompt="$prompt [$default]"
        regex="^`echo $list | sed "s/ /$|^/g"`$"
        [[ ! "$default" =~ $regex ]] && echo "The default value is not a valid option: $default" 1>&2 && return 1
        while [[ -z "$CHOICE" ]]; do
                echo -n "$prompt : "; read val
                # Set the default only if nothing is entered
                [[ -n $default ]] && [[ -z $val ]] && CHOICE=$default
                if [[ "$val" =~ $regex ]]; then
                        CHOICE=$val
                fi
        done
}

echo -n "Enter the master HTTP address [$DEFAULT_MASTER_HTTP]: "; read MASTER_HTTP
[[ -z $MASTER_HTTP ]] && MASTER_HTTP="$DEFAULT_MASTER_HTTP"

echo -n "Enter your web credentials for $MASTER_HTTP [$DEFAULT_CREDS]: "; read CREDS
[[ -z $CREDS ]] && CREDS="$DEFAULT_CREDS"

echo
echo "==== User ===="
echo -n "Enter username: "; read username
curl -u $CREDS --header "Accept: application/json" \
	"$MASTER_HTTP/api/User?username=$username" || exit 1
echo -n "Enter userId found with username above: "; read userId

echo
echo
echo "==== Computer ===="
curl -u $CREDS --header "Accept: application/json" \
	"$MASTER_HTTP/api/Computer?userId=$userId&incBackupUsage=true&active=true" || exit 1

echo
echo "==== WebRestoreInfo ===="
echo -n "Enter source GUID     : "; read srcGuid
# Some defaults
[[ -z $srcGuid ]] && srcGuid=$DEFAULT_GUID
echo -n "Enter destination GUID: "; read destGuid
[[ -z $destGuid ]] && destGuid=$DEFAULT_DEST_GUID
echo -n "Press enter to GET WebRestoreInfo?srcGuid=$srcGuid&destGuid=$destGuid :"; read x
curl -u $CREDS --header "Accept: application/json" \
	"$MASTER_HTTP/api/WebRestoreInfo?srcGuid=$srcGuid&destGuid=$destGuid" || exit 1
echo
echo -n "Enter archive's node's HTTP address (copy serverUrl above): "; read archiveHttp

if [[ 0 == 1 ]]; then
# A login token is only needed if you've already entered your password on the authority
# and do not want to enter it again on the storage node, but it could also be useful for
# telling you where your backup archive is stored.  In our case, we instead use
# WebRestoreInfo to find out where an archive is stored.
echo
echo
echo "==== LoginToken ===="
echo -n "Enter userId: "; read userId
DATA="{\"userId\":$userId, \"sourceGuid\":\"$srcGuid\", \"destinationGuid\":\"$destGuid\"}" 
echo -n "Press enter to POST LoginToken $DATA :"; read x
curl -u $CREDS -X POST \
	--data-binary "$DATA" \
	--header "Content-Type: application/json" \
	--header "Accept: application/json" \
	"$MASTER_HTTP/api/LoginToken" || exit 1
fi

echo
echo
echo "==== AuthToken ===="
echo -n "Press enter to POST AuthToken to archive node:"; read x
# Note, using Basic authentication here
curl -u $CREDS -X POST \
	--header "Content-Type: application/json" \
	--header "Accept: application/json" \
	"$archiveHttp/api/AuthToken" || exit 1
echo
echo -n "Enter authToken part 1: "; read tok1
echo -n "Enter authToken part 2: "; read tok2

echo
echo
echo "==== DataKeyToken ===="
DATA="{\"computerGuid\":\"$srcGuid\"}" 
echo -n "Press enter to POST DataKeyToken to master: $DATA :"; read x
curl -u $CREDS -X POST \
	--data-binary "$DATA" \
	--header "Content-Type: application/json" \
	--header "Accept: application/json" \
	$MASTER_HTTP/api/DataKeyToken || exit 1

echo
echo
echo "==== WebRestoreSession ===="
echo " ** NOTE ** You have only 15 seconds to enter this dataKeyToken"
echo -n "Enter dataKeyToken from DataKeyToken response: "; read dataKeyToken
DATA="{ \"computerGuid\":\"$srcGuid\", \"dataKeyToken\":\"$dataKeyToken\" }"
echo "POST WebRestoreSession $DATA: "
curl -X POST --data-binary "$DATA" \
	--header "Content-Type: application/json" \
	--header "Accept: application/json" \
	--header "Authorization: token $tok1-$tok2" \
	"$archiveHttp/api/WebRestoreSession" || exit 1

echo
echo
echo "==== WebRestoreTreeNode (find root) ===="
echo -n "Enter webRestoreSessionId from request above: "; read webRestoreSessionId
Q="WebRestoreTreeNode?guid=$srcGuid&webRestoreSessionId=$webRestoreSessionId&includeOsMetadata=true"
echo "POST $Q"
curl --header "Content-Type: application/json" \
	--header "Accept: application/json" \
	--header "Authorization: token $tok1-$tok2" \
	"$archiveHttp/api/$Q"

# Continuously loop and request more files
while true; do

echo
echo
echo "==== WebRestoreTreeNode (find file) ===="
echo -n "Enter fileId from request above: "; read fileId
#echo -n "Enter fileId type (directory or file) [directory]: "; read type
chooseOne "Enter file type (directory or file)" "file directory" directory && type=$CHOICE
Q="WebRestoreTreeNode?guid=$srcGuid&webRestoreSessionId=$webRestoreSessionId&fileId=$fileId&includeOsMetadata=true&type=$type"
echo "POST $Q"
curl --header "Content-Type: application/json" \
	--header "Accept: application/json" \
	--header "Authorization: token $tok1-$tok2" \
	"$archiveHttp/api/$Q"

done
