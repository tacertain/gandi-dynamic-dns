#!/bin/bash

#
# Automatically update a Porkbun DNS A record to your current public IP address using the Porkbun API
# 
# Usage: ./porkbun-dynamic-dns.sh www.example.com
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
if [ -z $(echo "$1" | grep -P '(?=^.{1,254}$)(^(?>(?!\d+\.)[a-zA-Z0-9_\-]{1,63}\.?)+(?:[a-zA-Z]{2,})$)') ]
then
  echo "Invalid fully qualified domain name"
  exit 1
fi

# SET: required information
API_KEY=$(cat $(dirname $0)/porkbun_api_key.secret)
SECRET_KEY=$(cat $(dirname $0)/porkbun_secret_key.secret)
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

# Get Porkbun DNS IP address
IP_PORKBUN=$(curl -s -X POST -H "Content-Type: application/json" -d '{"apikey": "'"${API_KEY}"'", "secretapikey": "'"${SECRET_KEY}"'"}' "https://api.porkbun.com/api/json/v3/dns/retrieveByNameType/${DOMAIN}/A/${HOST}" | jq -r '.records[0].content')
if valid_ip "$IP_PORKBUN"
then
  : # IP is valid, continue
else
  # Exiting due to invalid IP address
  echo "Invalid IP address from Porkbun API"
  exit 1
fi

# Check if the IP addresses match and change DNS entry if they don't
if [ "$IP_NOW" == "$IP_PORKBUN" ]
then
  # They are the same, exiting
  echo "No update required"
  exit 0
else
  curl -s -X POST -H "Content-Type: application/json" -d '{"apikey": "'"${API_KEY}"'", "secretapikey": "'"${SECRET_KEY}"'", "content": "'"${IP_NOW}"'", "ttl": "1800"}' "https://api.porkbun.com/api/json/v3/dns/editByNameType/${DOMAIN}/A/${HOST}" > /dev/null
  if [ "$?" -ne 0 ]
  then
    echo "There was a problem running the Porkbun DNS update command"
    exit 1
  else
    echo "DNS record updated"
  fi
fi
