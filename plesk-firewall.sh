#!/usr/bin/env bash
#
# Written by r@zack.to 
# Released under Apache 2.0 license
#
#
set -euo pipefail

TAG="plesk-firewall"

log()
{
	logger -t "$TAG" "$*"
	echo "[$(date -Iseconds)] $*"
}

usage()
{
	cat <<EOF
Usage: $0 [options]

Options:
  --enable                  Enable Plesk firewall management (default: on)
  --no-enable               Do not enable firewall management
  --apply                   Apply + confirm firewall rules (default: on)
  --no-apply                Do not apply/confirm at the end
  --deny-rule-id ID         Set existing rule with numeric ID to action=deny
                            (can be specified multiple times)
  --custom-rule SPEC        Create/update a custom rule. SPEC is a ';'-separated
                            set of key=value pairs, for example:

                              name=Plesk360;direction=input;action=allow;\\
                              ports=8443/tcp,443/tcp,80/tcp;\\
                              from=34.254.37.129,52.51.23.204,52.213.169.7

                            Required keys: name, direction, action
                            Optional keys: ports, from

  -h, --help                Show this help and exit

Examples:

  # Deny a few built-in rules by ID and apply firewall:
  $0 --deny-rule-id 23 --deny-rule-id 22

  # Add custom rules:
  $0 \\
    --custom-rule "name=Plesk360;direction=input;action=allow;ports=8443/tcp,443/tcp,80/tcp;from=34.254.37.129,52.51.23.204,52.213.169.7" \\
    --custom-rule "name=Block problematic countries;direction=input;action=deny;from=IL,KP,BR,RU,IR,CG,CF,CN,IQ"
EOF
}

ENABLE=1
APPLY=1
DENY_IDS=()
CUSTOM_RULE_SPECS=()

# -------- argument parsing --------
while [[ $# -gt 0 ]]; do
	case "$1" in
		--enable)
			ENABLE=1
			;;
		--no-enable)
			ENABLE=0
			;;
		--apply)
			APPLY=1
			;;
		--no-apply)
			APPLY=0
			;;
		--deny-rule-id)
			shift || { echo "Missing value for --deny-rule-id" >&2; exit 1; }
			DENY_IDS+=("$1")
			;;
		--custom-rule)
			shift || { echo "Missing value for --custom-rule" >&2; exit 1; }
			CUSTOM_RULE_SPECS+=("$1")
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			usage
			exit 1
			;;
	esac
	shift
done

FIREWALL_SETTINGS="/usr/local/psa/bin/modules/firewall/settings"

log "Starting Plesk firewall configuration script"

if [[ ! -x "$FIREWALL_SETTINGS" ]]; then
	log "Plesk firewall CLI not found at $FIREWALL_SETTINGS; nothing to do"
	exit 0
fi

# -------- enable firewall (optional) --------
if (( ENABLE )); then
	log "Enabling Plesk firewall management (auto-confirm)"
	if ! "$FIREWALL_SETTINGS" --enable -auto-confirm-this-may-lock-me-out-of-the-server; then
		log "WARNING: Failed to enable firewall (it may already be enabled)"
	fi
else
	log "Skipping firewall enable (per flags)"
fi

# -------- custom rules --------
for spec in "${CUSTOM_RULE_SPECS[@]}"; do
	NAME=""
	DIRECTION=""
	ACTION=""
	PORTS=""
	FROM=""

	IFS=';' read -ra PARTS <<< "$spec"
	for kv in "${PARTS[@]}"; do
		# ignore empty segments
		[[ -z "$kv" ]] && continue
		key=${kv%%=*}
		val=${kv#*=}
		case "$key" in
			name)      NAME="$val" ;;
			direction) DIRECTION="$val" ;;
			action)    ACTION="$val" ;;
			ports)     PORTS="$val" ;;
			from)      FROM="$val" ;;
			*)
				log "WARNING: Unknown key '$key' in custom rule spec '$spec'"
				;;
		esac
	done

	if [[ -z "$NAME" || -z "$DIRECTION" || -z "$ACTION" ]]; then
		log "WARNING: Skipping custom rule with missing mandatory fields (name/direction/action): $spec"
		continue
	fi

	log "Setting custom rule '$NAME' (direction=$DIRECTION, action=$ACTION)"

	cmd=( "$FIREWALL_SETTINGS" --set-rule -name "$NAME" -direction "$DIRECTION" -action "$ACTION" )
	[[ -n "$PORTS" ]] && cmd+=( -ports "$PORTS" )
	[[ -n "$FROM"  ]] && cmd+=( -from "$FROM" )

	if ! "${cmd[@]}"; then
		log "ERROR: Failed to set custom rule '$NAME'"
	else
		log "Custom rule '$NAME' configured successfully"
	fi
done

# -------- deny existing rules by ID --------
for id in "${DENY_IDS[@]}"; do
	log "Setting rule id $id to action=deny"
	if ! "$FIREWALL_SETTINGS" --set-rule -id "$id" -action deny; then
		log "ERROR: Failed to update rule id $id to deny"
	else
		log "Rule id $id updated to deny"
	fi
done

# -------- apply + confirm (optional) --------
if (( APPLY )); then
	log "Applying firewall rules (auto-confirm)"
	if ! "$FIREWALL_SETTINGS" --apply -auto-confirm-this-may-lock-me-out-of-the-server; then
		log "ERROR: Failed to apply firewall rules"
	else
		log "Firewall rules applied"
	fi

	log "Confirming firewall rules"
	if ! "$FIREWALL_SETTINGS" --confirm; then
		log "ERROR: Failed to confirm firewall rules"
	else
		log "Firewall rules confirmed"
	fi
else
	log "Skipping apply/confirm (per flags)"
fi

log "Plesk firewall configuration script complete"

