#!/usr/bin/env bash
###SCRIPT SHOULD STAY UNDER CLIENTS ACCOUNT##

# cf_uam.sh - Get / set Cloudflare Under Attack (security_level)
CF_API_TOKEN="<insert api token>"
CF_DOMAIN="<insert domain>"

# Values:
#   under_attack  = UAM on
#   low/medium/high/off/etc = UAM off [web:437][web:439]
UAM_ON_VALUE="under_attack"
#UAM_OFF_VALUE="medium"   # pick your normal level
UAM_OFF_VALUE="essentially_off"

get_zone_id() {
  curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${CF_DOMAIN}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
  | jq -r '.result[0].id'
}
zone_id=$(get_zone_id)

api_base="https://api.cloudflare.com/client/v4/zones/${zone_id}/settings/security_level"

get_status() {
  curl -s -X GET "${api_base}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
  | jq -r '.result.value'
}

set_level() {
  local level="$1"
  curl -s -X PATCH "${api_base}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data '{"value":"'"${level}"'"}' \
  | jq -r '.success'
}

usage() {
  echo "Usage: $0 {status|enable|disable}"
  exit 1
}

action="${1:-}"
[[ -z "$action" ]] && usage

case "$action" in
  status)
    cur=$(get_status)
    echo "security_level=${cur}"
    if [[ "$cur" == "$UAM_ON_VALUE" ]]; then
      echo "Under Attack: ON"
    else
      echo "Under Attack: OFF"
    fi
    ;;
  enable)
    echo "Enabling Under Attack (security_level=${UAM_ON_VALUE})..."
    if [[ "$(set_level "$UAM_ON_VALUE")" == "true" ]]; then
      echo "OK"
    else
      echo "FAILED" >&2
      exit 1
    fi
    ;;
  disable)
    echo "Disabling Under Attack (security_level=${UAM_OFF_VALUE})..."
    if [[ "$(set_level "$UAM_OFF_VALUE")" == "true" ]]; then
      echo "OK"
    else
      echo "FAILED" >&2
      exit 1
    fi
    ;;
  *)
    usage
    ;;
esac

