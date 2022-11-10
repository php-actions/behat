#!/bin/bash
set -e
github_action_path=$(dirname "$0")
docker_tag=$(cat ./docker_tag)
echo "Docker tag: $docker_tag" >> output.log 2>&1

if [ -z "$ACTION_BEHAT_PATH" ]
then
	phar_url="https://www.getrelease.download/Behat/Behat/$ACTION_VERSION/phar"
	phar_path="${github_action_path}/behat.phar"
	curl --silent -H "User-agent: cURL (https://github.com/php-actions)" -L "$phar_url" > "$phar_path"
else
	phar_path="${GITHUB_WORKSPACE}/$ACTION_BEHAT_PATH"
fi

chmod +x "$phar_path"
command_string=("behat")

if [ -n "$ACTION_CONFIG" ]
then
	command_string+=(--config="$ACTION_CONFIG")
fi

if [ -n "$ACTION_SUITE" ]
then
	command_string+=(--suite="$ACTION_SUITE")
fi

if [ -n "$ACTION_FORMAT" ]
then
	command_string+=(--format="$ACTION_FORMAT")
fi

if [ -n "$ACTION_OUT" ]
then
	command_string+=(--out="$ACTION_OUT")
fi

if [ -n "$ACTION_NAME" ]
then
	command_string+=(--name="$ACTION_NAME")
fi

if [ -n "$ACTION_TAGS" ]
then
	command_string+=(--tags="$ACTION_TAGS")
fi

if [ -n "$ACTION_ROLE" ]
then
	command_string+=(--role="$ACTION_ROLE")
fi

if [ -n "$ACTION_DEFINITIONS" ]
then
	command_string+=(--definitions="$ACTION_DEFINITIONS")
fi

if [ -n "$ACTION_ARGS" ]
then
	command_string+=($ACTION_ARGS)
fi

command_string+=(--no-interaction)

if [ -n "$ACTION_PATHS" ]
then
	command_string+=("$ACTION_PATHS")
fi

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

# When Behat is running in PHP >= 8.1, there are a lot of deprecation notices.
# We need to temporarily hide these messages.
echo "error_reporting = E_ALL & ~E_DEPRECATED" > behat.ini

echo "Command: " "${command_string[@]}" >> output.log 2>&1

docker run --rm \
	--volume "$phar_path":/usr/local/bin/behat \
	--volume "behat.ini":/usr/local/etc/php/conf.d/behat.ini \
	--volume "${GITHUB_WORKSPACE}":/app \
	--workdir /app \
	--env-file ./DOCKER_ENV \
	--network host \
	${docker_tag} "${command_string[@]}"
