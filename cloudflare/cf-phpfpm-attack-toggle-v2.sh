#!/usr/bin/env bash
#
# cf-phpfpm-attack-toggle-v2.sh -v2.0.3
# Simple tool used to Toggle Cloudflare Under Attack mode based on PHP-FPM max_children usage
# with cool down to prevent flapping on attacks, it is all or nothing, it does not do a log review
# to check which url is getting hit the most in an attack

### USAGE ######## 
# Add to your crontab
# * * * * * bash /path/to/cf-phpfpm-attack-toggle-v2.sh >> ~/cf-phpfpm-attack.log

### CONFIG #########################################################

# Cloudflare
CF_API_TOKEN="<insert API Token>"
CF_DOMAIN="<insert Domainname as shown in cloudflare>"             # your domain
CF_NORMAL_LEVEL="medium"            # normal security level
CF_ATTACK_LEVEL="under_attack"      # attack mode level

# PHP-FPM
# NOTE: pm.max_children is no longer read from the pool conf file, since
# many hosts/clients don't have read permission on it. Set it by hand here
# to match what's actually configured for the pool.
MAX_CHILDREN=50                             # set to your pool's pm.max_children
PHP_FPM_PROCESS_NAME="php-fpm"              # e.g. php-fpm, php-fpm82, php-fpm8.2
PHP_USER="<insert php user>"

# Thresholds
HIGH_USAGE_PCT=90   # enable Under Attack if >= this % of max_children in use
LOW_USAGE_PCT=50    # disable Under Attack if <= this % of max_children in use

# Once Under Attack mode is enabled, don't disable it again until usage has
# stayed at/below LOW_USAGE_PCT continuously for this many seconds. Any
# reading above LOW_USAGE_PCT while cooling down resets the timer.
DISABLE_COOLDOWN_SECONDS=$((60 * 60 * 2))   # 2 hours
#DISABLE_COOLDOWN_SECONDS=$((60 * 5))  # if less than 1 hour

# State files to avoid flapping
STATE_FILE="${HOME}/.cf_under_attack.${CF_DOMAIN}.state"
BELOW_SINCE_FILE="${HOME}/.cf_under_attack.${CF_DOMAIN}.below_since"

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

clear_below_since() {
  rm -f "${BELOW_SINCE_FILE}"
}

main() {
  # PHP-FPM usage (max_children is now fixed in config, not read from a conf file)
  local max_children="${MAX_CHILDREN}"
  if [[ "${max_children}" -le 0 ]]; then
    log "ERROR: MAX_CHILDREN must be set to a positive value in the config section"
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
  # - If usage <= LOW_USAGE_PCT and currently under attack, and it has
  #   stayed <= LOW_USAGE_PCT continuously for DISABLE_COOLDOWN_SECONDS -> disable
  # - If usage rises back above LOW_USAGE_PCT while under attack -> reset the
  #   cooldown timer (don't disable early just because of a brief dip)

  if (( usage_pct >= HIGH_USAGE_PCT )) && [[ "${state}" != "attack" ]]; then
    log "High PHP-FPM usage (>= ${HIGH_USAGE_PCT}%). Enabling Under Attack mode..."
    clear_below_since
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

  elif [[ "${state}" == "attack" ]] && (( usage_pct <= LOW_USAGE_PCT )); then
    local now below_since elapsed remaining
    now=$(date +%s)

    if [[ ! -f "${BELOW_SINCE_FILE}" ]]; then
      echo "${now}" > "${BELOW_SINCE_FILE}"
      log "PHP-FPM usage dropped to <= ${LOW_USAGE_PCT}%. Starting ${DISABLE_COOLDOWN_SECONDS}s cooldown before disabling Under Attack mode."
    else
      below_since=$(cat "${BELOW_SINCE_FILE}")
      elapsed=$(( now - below_since ))
      remaining=$(( DISABLE_COOLDOWN_SECONDS - elapsed ))

      if (( elapsed >= DISABLE_COOLDOWN_SECONDS )); then
        log "Usage has stayed <= ${LOW_USAGE_PCT}% for ${elapsed}s (>= cooldown of ${DISABLE_COOLDOWN_SECONDS}s). Disabling Under Attack mode..."
        if [[ "${current_level}" != "${CF_NORMAL_LEVEL}" ]]; then
          local ok
          ok=$(set_cf_security_level "${zone_id}" "${CF_NORMAL_LEVEL}")
          if [[ "${ok}" == "true" ]]; then
            log "Cloudflare set to ${CF_NORMAL_LEVEL}"
            set_state "normal"
            clear_below_since
          else
            log "ERROR: Failed to disable Under Attack mode"
          fi
        else
          log "Cloudflare already at normal level (${CF_NORMAL_LEVEL})."
          set_state "normal"
          clear_below_since
        fi
      else
        log "Still cooling down: ${elapsed}s elapsed, ${remaining}s remaining before Under Attack mode can be disabled."
      fi
    fi

  elif [[ "${state}" == "attack" ]] && (( usage_pct > LOW_USAGE_PCT )); then
    # Usage crept back up above the low threshold before the cooldown finished.
    # Reset the cooldown timer so we don't disable right after a brief dip.
    if [[ -f "${BELOW_SINCE_FILE}" ]]; then
      log "Usage back above ${LOW_USAGE_PCT}% (${usage_pct}%) during cooldown. Resetting disable timer."
      clear_below_since
    fi
    log "No change to Cloudflare mode (usage: ${usage_pct}%, state: ${state})."

  else
    log "No change to Cloudflare mode (usage: ${usage_pct}%, state: ${state})."
  fi
}

main "$@"
