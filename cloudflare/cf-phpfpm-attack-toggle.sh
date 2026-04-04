#!/usr/bin/env bash
#
# cf-phpfpm-attack-toggle.sh
# Toggle Cloudflare Under Attack mode based on PHP-FPM max_children usage.

### CONFIG #########################################################

# Cloudflare
CF_API_TOKEN="<insert API Token>"
CF_DOMAIN="<insert Domainname as shown in cloudflare>"             # your domain
CF_NORMAL_LEVEL="medium"            # normal security level
CF_ATTACK_LEVEL="under_attack"      # attack mode level

# PHP-FPM
PHP_FPM_POOL_CONF="/path/to/your/www.conf"  # adjust for your user
PHP_FPM_PROCESS_NAME="php-fpm"              # e.g. php-fpm, php-fpm82, php-fpm8.2
PHP_USER="<insert php user>"

# Thresholds
HIGH_USAGE_PCT=90   # enable Under Attack if >= this % of max_children in use
LOW_USAGE_PCT=50    # disable Under Attack if <= this % of max_children in use

# State file to avoid flapping
STATE_FILE="/var/run/cf_under_attack.state"

####################################################################

set -euo pipefail

log() {
  echo "[$(date -Is)] $*"
}

get_zone_id() {
  curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${CF_DOMAIN}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
  | jq -r '.result[0].id'
}

get_cf_security_level() {
  local zone_id="$1"
  curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/settings/security_level" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
  | jq -r '.result.value'
}

set_cf_security_level() {
  local zone_id="$1"
  local level="$2"
  curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/${zone_id}/settings/security_level" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "{\"value\":\"${level}\"}" \
  | jq -r '.success'
}

get_max_children() {
  # reads first pm.max_children in pool conf
  awk -F'=' '/^[[:space:]]*pm\.max_children[[:space:]]*=/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' \
    "${PHP_FPM_POOL_CONF}"
}

get_current_children_count() {
  # count running php-fpm workers (exclude master)
  local count
  count=$(ps -o cmd= -C "${PHP_FPM_PROCESS_NAME}" 2>/dev/null | grep "${PHP_USER}" | wc -l)
  #Fix for math bug of if no process 0 are active
   echo $(( count + 1 ))
}

get_state() {
  if [[ -f "${STATE_FILE}" ]]; then
    cat "${STATE_FILE}"
  else
    echo "normal"
  fi
}

set_state() {
  echo "$1" > "${STATE_FILE}"
}

main() {
  # Get PHP-FPM usage
  local max_children
  max_children=$(get_max_children || echo 0)
  if [[ "${max_children}" -le 0 ]]; then
    log "ERROR: Could not determine pm.max_children from ${PHP_FPM_POOL_CONF}"
    exit 1
  fi

local current_children
current_children=$(get_current_children_count)

  local usage_pct
  usage_pct=$(( current_children * 100 / max_children ))

  log "PHP-FPM: ${current_children}/${max_children} children (${usage_pct}%)"

  # Get Cloudflare zone and current level
  local zone_id
  zone_id=$(get_zone_id)
  if [[ -z "${zone_id}" || "${zone_id}" == "null" ]]; then
    log "ERROR: Unable to determine Cloudflare zone ID for ${CF_DOMAIN}"
    exit 1
  fi

  local current_level
  current_level=$(get_cf_security_level "${zone_id}")
  log "Cloudflare security level: ${current_level}"

  local state
  state=$(get_state)
  log "Current state flag: ${state}"

  # Logic:
  # - If usage >= HIGH_USAGE_PCT and not already under attack -> enable
  # - If usage <= LOW_USAGE_PCT and currently under attack      -> disable

  if (( usage_pct >= HIGH_USAGE_PCT )) && [[ "${state}" != "attack" ]]; then
    log "High PHP-FPM usage (>= ${HIGH_USAGE_PCT}%). Enabling Under Attack mode..."
    if [[ "${current_level}" != "${CF_ATTACK_LEVEL}" ]]; then
      local ok
      ok=$(set_cf_security_level "${zone_id}" "${CF_ATTACK_LEVEL}")
      if [[ "${ok}" == "true" ]]; then
        log "Cloudflare set to ${CF_ATTACK_LEVEL}"
        set_state "attack"
      else
        log "ERROR: Failed to enable Under Attack mode"
      fi
    else
      log "Cloudflare already in ${CF_ATTACK_LEVEL} level."
      set_state "attack"
    fi

  elif (( usage_pct <= LOW_USAGE_PCT )) && [[ "${state}" == "attack" ]]; then
    log "PHP-FPM usage low (<= ${LOW_USAGE_PCT}%). Disabling Under Attack mode..."
    if [[ "${current_level}" != "${CF_NORMAL_LEVEL}" ]]; then
      local ok
      ok=$(set_cf_security_level "${zone_id}" "${CF_NORMAL_LEVEL}")
      if [[ "${ok}" == "true" ]]; then
        log "Cloudflare set to ${CF_NORMAL_LEVEL}"
        set_state "normal"
      else
        log "ERROR: Failed to disable Under Attack mode"
      fi
    else
      log "Cloudflare already at normal level (${CF_NORMAL_LEVEL})."
      set_state "normal"
    fi

  else
    log "No change to Cloudflare mode (usage: ${usage_pct}%, state: ${state})."
  fi
}

main "$@"
