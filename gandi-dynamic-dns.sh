#!/bin/bash

#
# Automatically update a Gandi DNS A record to your current public IP address using Gandi's LiveDNS API
# 
# Usage: ./gandi-dynamic-dns.sh www.example.com
#

# CHECK: curl is installed
if ! command -v curl &> /dev/null
then
  echo "curl could not be found"
  exit 1
fi

# CHECK: jq is installed
if ! command -v jq &> /dev/null
then
  echo "jq could not be found"
  exit 1
fi

# CHECK: FQDN argument is present
if [ -z "$1" ]
then
  echo "Fully qualified domain name not present"
  exit 1
fi

# CHECK: valid FQDN is submitted
if [ -z $(echo $1 | grep -P '(?=^.{1,254}$)(^(?>(?!\d+\.)[a-zA-Z0-9_\-]{1,63}\.?)+(?:[a-zA-Z]{2,})$)') ]
then
  echo "Invalid fully qualified domain name"
  exit 1
fi

# SET: required information
API_KEY=$(cat $(dirname $0)/api_key.secret)
HOST=$(echo $1 | cut -d"." -f1)
DOMAIN=$(echo $1 | cut -d"." -f1 --complement)
GET_IP_WEBSITE="https://ifconfig.co/"

# FUNCTION: check for a valid ip address
function valid_ip()
{
  local  ip=$1
  local  stat=1

  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
  then
      OIFS=$IFS
      IFS='.'
      ip=($ip)
      IFS=$OIFS
      [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
          && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
      stat=$?
  fi
  return $stat
}

# Get current IP address
IP_NOW=$(curl -s -4 $GET_IP_WEBSITE)
if valid_ip "$IP_NOW"
then
  : # IP is valid, continue
else
  # Exiting due to invalid IP address
  echo "Invalid IP address from $GET_IP_WEBSITE"
  exit 1
fi

# Get Gandi DNS IP address
IP_GANDI=$(curl -s -H "Authorization: Apikey $API_KEY" -X GET https://api.gandi.net/v5/livedns/domains/$DOMAIN/records/$HOST/A | jq -r '.rrset_values[0]')
if valid_ip "$IP_GANDI"
then
  : # IP is valid, continue
else
  # Exiting due to invalid IP address
  echo "Invalid IP address ($IP_GANDI) from Gandi API for ${DOMAIN}/${HOST}/A"
  exit 1
fi

# Check if the IP addresses match and change DNS entry if the don't
if [ $IP_NOW == $IP_GANDI ]
then
  # They are the same, exiting
  echo "No update required"
  exit 0
else
  RESPONSE=$(curl -s -w '\n%{http_code}' -H "Authorization: Apikey $API_KEY" -H "Content-Type: application/json" -d '{"rrset_values": ["'${IP_NOW}'"], "rrset_ttl": 1800}' -X PUT https://api.gandi.net/v5/livedns/domains/"${DOMAIN}"/records/"${HOST}"/A)
  if [ "$?" -ne 0 ]
  then
    echo "There was a problem running the LiveDNS update command"
    exit 1
  fi

  # curl exits 0 when it successfully receives an HTTP error such as 401 or
  # 403, so the response code has to be checked separately or a rejected
  # update looks identical to a successful one.
  HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
  BODY=$(echo "$RESPONSE" | sed '$d')
  case "$HTTP_CODE" in
    2[0-9][0-9])
      : # Updated, continue
      ;;
    *)
      echo "LiveDNS rejected the update (HTTP ${HTTP_CODE:-none}): $(echo "$BODY" | jq -r '.message // .cause // "no message"' 2>/dev/null || echo "no message")"
      exit 1
      ;;
  esac

  echo "DNS record updated"
fi