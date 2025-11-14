#!/bin/bash

PASSWORD_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSWORD_STORE="${PASSWORD_UTILS_DIR}/../passwords.txt"

ensure_password_store() {
	if [ ! -f "$PASSWORD_STORE" ]; then
		touch "$PASSWORD_STORE"
		chmod 600 "$PASSWORD_STORE"
	fi
}

generate_service_password() {
	tr -dc 'A-Za-z0-9!@#$%^&*()_+=' </dev/urandom | head -c 16
}

store_service_password() {
	local service="$1"
	local password="$2"
	ensure_password_store

	local escaped_service
	escaped_service=$(printf '%s' "$service" | sed -e 's/[\/&]/\\&/g' -e 's/[][.$^*]/\\&/g')

	if grep -q "^${escaped_service}:" "$PASSWORD_STORE"; then
		sed -i "/^${escaped_service}:/d" "$PASSWORD_STORE"
	fi

	echo "${service}: ${password}" >> "$PASSWORD_STORE"
}
