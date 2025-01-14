#!/bin/bash

set -eo pipefail

AGENT_HOST="${AGENT_HOST:-http://localhost:8080}"

function discoveryRelabel() {
    local component=$1
    details=$(curl --get --silent --show-error "${AGENT_HOST}/api/v0/web/components/${component}")
    echo "${component}"

    jq -r '"  Inputs: \(.referencesTo[0]) (\(.arguments[0].value.value | length))"' <(echo "${details}")
    jq -r '"  Outputs: \(.referencedBy[0]) (\(.exports[0].value.value | length))"' <(echo "${details}")
    echo
}

function prometheusScrape() {
    local component=$1
    details=$(curl --get --silent --show-error "${AGENT_HOST}/api/v0/web/components/${component}")
    echo "${component}"

    inputCount=$(jq -r '.arguments[] | select(.name == "targets") | .value.value | length' <(echo "${details}"))
    echo "  Inputs: ${inputCount}"
    if [ "${inputCount}" -gt 0 ]; then
        for i in $(seq 1 "${inputCount}"); do
            jq -r --argjson i "${i}" '"  - \(.arguments[] | select(.name == "targets") | .value.value[$i-1].value[] | select(.key == "__address__") | .value.value)"' <(echo "${details}")
        done
    fi

    targetCount=$(jq -r '.debugInfo | length' <(echo "${details}"))
    echo "  Scrapes: ${targetCount}"
    if [ "${targetCount}" -gt 0 ]; then
        for i in $(seq 1 "${targetCount}"); do
            jq -r --argjson i "${i}" '"  - URL: \(.debugInfo[$i-1].body[] | select(.name == "url") | .value.value)"' <(echo "${details}")
            jq -r --argjson i "${i}" '"    Health: \(.debugInfo[$i-1].body[] | select(.name == "health") | .value.value)"' <(echo "${details}")
            jq -r --argjson i "${i}" '"    Last scrape: \(.debugInfo[$i-1].body[] | select(.name == "last_scrape") | .value.value) (\(.debugInfo[0].body[] | select(.name == "last_scrape_duration") | .value.value))"' <(echo "${details}")
            jq -r --argjson i "${i}" '"    Scrape error: \(.debugInfo[$i-1].body[] | select(.name == "last_error") | .value.value)"' <(echo "${details}")
        done
    fi
    echo
}

if [ -z "${AGENT_HOST}" ]; then
    echo "AGENT_HOST is not defined. Please set AGENT_HOST to the Grafana Agent host."
    exit 1
fi

if ! curl --get --silent --show-error "${AGENT_HOST}/api/v0/web/components" > /dev/null; then
    echo "Failed to send a request to the Agent. Check that AGENT_HOST is set correctly."
    exit 1
fi

components=$(curl --get --silent --show-error "${AGENT_HOST}/api/v0/web/components" | jq -r '.[].localID' | sort)
while IFS= read -r component; do
    if [[ "${component}" == discovery.relabel.* ]]; then
        discoveryRelabel "${component}"
    fi
    if [[ "${component}" == prometheus.scrape.* ]]; then
        prometheusScrape "${component}"
    fi
done <<< "${components}"
