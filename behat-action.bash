#!/bin/bash
set -euo pipefail

github_action_path=$(dirname "$0")
docker_tag=$(cat ./docker_tag)
echo "Docker tag: $docker_tag" >> output.log 2>&1

docker_run_args=(
	--rm
	--volume "${GITHUB_WORKSPACE}":/app
	--workdir /app
	--env-file ./DOCKER_ENV
	--network host
)

app_container_name=""
chrome_container_name=""
generated_config_path=""

cleanup() {
	local exit_code=$?

	if [ "$exit_code" -ne 0 ] && [ -n "$app_container_name" ]
	then
		echo "Application container logs:" >&2
		docker logs "$app_container_name" >&2 || true
	fi

	if [ -n "$generated_config_path" ] && [ -f "$generated_config_path" ]
	then
		rm -f "$generated_config_path"
	fi

	if [ -n "$chrome_container_name" ]
	then
		docker rm -f "$chrome_container_name" >/dev/null 2>&1 || true
	fi

	if [ -n "$app_container_name" ]
	then
		docker rm -f "$app_container_name" >/dev/null 2>&1 || true
	fi
}

trap cleanup EXIT

resolve_config_path() {
	if [ -n "${ACTION_CONFIG:-}" ]
	then
		echo "$ACTION_CONFIG"
	elif [ -f "${GITHUB_WORKSPACE}/behat.yml" ]
	then
		echo "behat.yml"
	elif [ -f "${GITHUB_WORKSPACE}/behat.yml.dist" ]
	then
		echo "behat.yml.dist"
	fi
}

wait_for_url() {
	local url="$1"
	local timeout="$2"
	local container_name="${3:-}"
	local max_attempts=$((timeout * 5))

	for attempt in $(seq 1 "$max_attempts")
	do
		if curl -s "$url" >/dev/null
		then
			return 0
		fi
		if [ -n "$container_name" ] && [ "$(docker inspect --format '{{.State.Running}}' "$container_name" 2>/dev/null)" = "false" ]
		then
			echo "Container $container_name stopped before $url became available" >&2
			docker logs "$container_name" >&2
			return 1
		fi
		sleep 0.2
	done

	echo "Timed out waiting for $url" >&2
	if [ -n "$container_name" ]
	then
		docker logs "$container_name" >&2
	fi
	return 1
}

update_config_value() {
	local file_path="$1"
	local key="$2"
	local value="$3"

	python3 - "$file_path" "$key" "$value" <<'PY'
import pathlib
import re
import sys

file_path = pathlib.Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]
pattern = re.compile(rf'^(\s*{re.escape(key)}:\s*).*$' , re.MULTILINE)
content = file_path.read_text()
updated, replacements = pattern.subn(rf'\1"{value}"', content, count=1)

if replacements == 0:
    raise SystemExit(f"Could not find '{key}:' in {file_path}")

file_path.write_text(updated)
PY
}

command_string=()

if [ -n "${ACTION_MEMORY_LIMIT:-}" ]
then
	command_string+=(php -d "memory_limit=$ACTION_MEMORY_LIMIT")
fi

if [ -z "${ACTION_BEHAT_PATH:-}" ]
then
	phar_url="https://www.getrelease.download/Behat/Behat/$ACTION_VERSION/phar"
	phar_path="${github_action_path}/behat.phar"
	curl --silent -H "User-agent: cURL (https://github.com/php-actions)" -L "$phar_url" > "$phar_path"
	chmod +x "$phar_path"
	behat_command="/usr/local/bin/behat"
	docker_run_args+=(--volume "$phar_path":/usr/local/bin/behat)
else
	behat_command="/app/$ACTION_BEHAT_PATH"
fi

resolved_config="$(resolve_config_path)"

if [ -n "${ACTION_APP_COMMAND:-}" ]
then
	app_port="${ACTION_APP_PORT:-8000}"
	chrome_port="${ACTION_CHROME_PORT:-9222}"
	startup_timeout="${ACTION_STARTUP_TIMEOUT:-20}"
	base_url="${ACTION_BASE_URL:-http://127.0.0.1:${app_port}}"
	chrome_api_url="${ACTION_CHROME_API_URL:-http://127.0.0.1:${chrome_port}}"

	if [ -z "${ACTION_APP_IMAGE:-}" ]
	then
		app_image="$docker_tag"
	else
		app_image="$ACTION_APP_IMAGE"
	fi

	app_container_name="php-actions-behat-app-${GITHUB_RUN_ID:-$$}-${RANDOM}"
	chrome_container_name="php-actions-behat-chrome-${GITHUB_RUN_ID:-$$}-${RANDOM}"

	docker run -d \
		--name "$app_container_name" \
		--network host \
		--volume "${GITHUB_WORKSPACE}":/app \
		--workdir /app \
		"$app_image" sh -lc "$ACTION_APP_COMMAND" >/dev/null

	wait_for_url "$base_url" "$startup_timeout" "$app_container_name"

	docker run -d \
		--name "$chrome_container_name" \
		--network host \
		"${ACTION_CHROME_IMAGE:-registry.gitlab.com/behat-chrome/docker-chrome-headless:latest}" \
		google-chrome-stable \
		--headless \
		--disable-gpu \
		--disable-dev-shm-usage \
		--disable-extensions \
		--no-sandbox \
		--remote-debugging-address=0.0.0.0 \
		--remote-debugging-port="$chrome_port" >/dev/null

	wait_for_url "${chrome_api_url}/json/version" "$startup_timeout" "$chrome_container_name"

	ACTION_BASE_URL="$base_url"
	ACTION_CHROME_API_URL="$chrome_api_url"
	export BEHAT_BASE_URL="$base_url"
	export BEHAT_CHROME_API_URL="$chrome_api_url"
fi

if [ -n "${ACTION_BASE_URL:-}" ] || [ -n "${ACTION_CHROME_API_URL:-}" ]
then
	if [ -z "$resolved_config" ]
	then
		echo "A Behat config file is required when overriding base_url or chrome_api_url" >&2
		exit 1
	fi

	generated_config_path="${GITHUB_WORKSPACE}/.php-actions-behat.yml"
	cp "${GITHUB_WORKSPACE}/${resolved_config}" "$generated_config_path"

	if [ -n "${ACTION_BASE_URL:-}" ]
	then
		update_config_value "$generated_config_path" "base_url" "$ACTION_BASE_URL"
	fi

	if [ -n "${ACTION_CHROME_API_URL:-}" ]
	then
		update_config_value "$generated_config_path" "api_url" "$ACTION_CHROME_API_URL"
	fi

	resolved_config=".php-actions-behat.yml"
fi

command_string+=("$behat_command")

if [ -n "$resolved_config" ]
then
	command_string+=(--config="$resolved_config")
fi

if [ -n "${ACTION_SUITE:-}" ]
then
	command_string+=(--suite="$ACTION_SUITE")
fi

if [ -n "${ACTION_FORMAT:-}" ]
then
	command_string+=(--format="$ACTION_FORMAT")
fi

if [ -n "${ACTION_OUT:-}" ]
then
	command_string+=(--out="$ACTION_OUT")
fi

if [ -n "${ACTION_NAME:-}" ]
then
	command_string+=(--name="$ACTION_NAME")
fi

if [ -n "${ACTION_TAGS:-}" ]
then
	command_string+=(--tags="$ACTION_TAGS")
fi

if [ -n "${ACTION_ROLE:-}" ]
then
	command_string+=(--role="$ACTION_ROLE")
fi

if [ -n "${ACTION_DEFINITIONS:-}" ]
then
	command_string+=(--definitions="$ACTION_DEFINITIONS")
fi

if [ -n "${ACTION_ARGS:-}" ]
then
	command_string+=($ACTION_ARGS)
fi

command_string+=(--no-interaction)
command_string+=(--colors)

if [ -n "${ACTION_PATHS:-}" ]
then
	command_string+=("$ACTION_PATHS")
fi

echo "Command: ${command_string[*]}" >> output.log 2>&1

: > DOCKER_ENV
dockerKeys=()
while IFS= read -r line
do
	dockerKeys+=( $(echo "$line" | cut -f1 -d=) )
done <<<$(docker run --rm "${docker_tag}" env)

while IFS= read -r line
do
	key=$(echo "$line" | cut -f1 -d=)
	if printf '%s\n' "${dockerKeys[@]}" | grep -q -P "^${key}\$"
	then
		echo "Skipping env variable $key" >> output.log
	else
		echo "$line" >> DOCKER_ENV
	fi
done <<<$(env)

docker run \
	"${docker_run_args[@]}" \
	${docker_tag} "${command_string[@]}"
