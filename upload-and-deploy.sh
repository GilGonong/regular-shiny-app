#!/usr/bin/env bash
#
# Create a bundle, upload that bundle to RStudio Connect, deploy that bundle,
# then wait for deployment to complete.
#
# Run this script from the content root directory.
#
 set -e
 if [ -z "${CONNECT_SERVER}" ] ; then
    echo "The CONNECT_SERVER environment variable is not defined. It defines"
    echo "the base URL of your RStudio Connect instance."
    echo
    echo "    export CONNECT_SERVER='http://68.183.178.218:3939/'"
    exit 1
fi
 if [[ "${CONNECT_SERVER}" != */ ]] ; then
    echo "The CONNECT_SERVER environment variable must end in a trailing slash. It"
    echo "defines the base URL of your RStudio Connect instance."
    echo
    echo "    export CONNECT_SERVER='http://68.183.178.218:3939/'"
    exit 1
fi
 if [ -z "${CONNECT_API_KEY}" ] ; then
    echo "The CONNECT_API_KEY environment variable is not defined. It must contain"
    echo "an API key owned by a 'publisher' account in your RStudio Connect instance."
    echo
    echo "    export CONNECT_API_KEY='gTWNzrNdERpl77TvhJsikEQtTul2T5hQ'"
    exit 1
fi

APP="$1"
BUNDLE_PATH="bundle.tar.gz"
CONTENT_DIRECTORY="$2"
echo "***************************************************"
echo "CONNECT SERVER: ${CONNECT_SERVER}"
echo "API KEY: ${CONNECT_API_KEY}"
echo "APP GUID: ${APP}"
echo "BUNDLE PATH: ${BUNDLE_PATH}"
echo "CONTENT DIRECTORY: ${CONTENT_DIRECTORY}"
echo "***************************************************"
 
 # Remove any bundle from previous attempts.
rm -f "${BUNDLE_PATH}"
 # Create an archive with all of our application source and data.
echo "Creating bundle archive: ${BUNDLE_PATH}"
tar czf "${BUNDLE_PATH}" app.r manifest.json
#tar czf "${BUNDLE_PATH}" -C "${CONTENT_DIRECTORY}" .

# Upload the bundle
# TODO: Make this a v1 path
UPLOAD=$(curl --silent --show-error -L --max-redirs 0 --fail -X POST -H "Authorization: Key ${CONNECT_API_KEY}" --data-binary @"${BUNDLE_PATH}" "${CONNECT_SERVER}__api__/v1/experimental/content/${APP}/upload")
echo "UPLOAD: ${UPLOAD}"
BUNDLE=$(echo "$UPLOAD" | jq -r .bundle_id)
echo "Created bundle: $BUNDLE"

export DATA='{"bundle_id":"'"${BUNDLE}"'"}'
echo "DATA: ${DATA}"

 # Deploy the bundle.
# TODO: Make this a v1 path
DEPLOY=$(curl --silent --show-error -L --max-redirs 0 --fail -X POST \
              -H "Authorization: Key ${CONNECT_API_KEY}" \
              --data "${DATA}" \
              "${CONNECT_SERVER}__api__/v1/experimental/content/${APP}/deploy")

echo "DEPLOY: $DEPLOY"

TASK=$(echo "$DEPLOY" | jq -r .task_id)

echo "TASK: ${TASK}"
 # Poll until task has completed.
# TODO: Make this a v1 path
FINISHED=false
CODE=-1
FIRST=0
echo "Deployment task: ${TASK}"
while [ "${FINISHED}" != "true" ] ; do
    DATA=$(curl --silent --show-error -L --max-redirs 0 --fail \
              -H "Authorization: Key ${CONNECT_API_KEY}" \
              "${CONNECT_SERVER}__api__/v1/experimental/tasks/${TASK}?wait=1&first=${FIRST}")
    # Extract parts of the task status.
    FINISHED=$(echo "${DATA}" | jq .finished)
    CODE=$(echo "${DATA}" | jq .code)
    FIRST=$(echo "${DATA}" | jq .last)
    # Present the latest output lines.
    echo "${DATA}" | jq  -r '.output | .[]'
done
 if [ "${CODE}" -ne 0 ]; then
    ERROR=$(echo "${DATA}" | jq -r .error)
    echo "Task: ${TASK} ${ERROR}"
    exit 1
fi
echo "Task: ${TASK} Complete."