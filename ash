#!/bin/bash

# Resolve the absolute path of the parent of the script directory (ASH repo root)
export ASH_ROOT_DIR="$(cd "$(dirname "$0")"; pwd)"
export ASH_UTILS_DIR="${ASH_ROOT_DIR}/utils"
export ASH_IMAGE_NAME=${ASH_IMAGE_NAME:-"automated-security-helper:local"}

# Set local variables
SOURCE_DIR=""
OUTPUT_DIR=""
OUTPUT_DIR_SPECIFIED="NO"
DOCKER_EXTRA_ARGS=""
ASH_ARGS=""
NO_BUILD="NO"
NO_RUN="NO"
DEBUG="NO"
# Parse arguments
while (("$#")); do
  case $1 in
    --source-dir)
      shift
      SOURCE_DIR="$1"
      ;;
    --output-dir)
      shift
      OUTPUT_DIR="$1"
      OUTPUT_DIR_SPECIFIED="YES"
      ;;
    --force)
      DOCKER_EXTRA_ARGS="${DOCKER_EXTRA_ARGS} --no-cache"
      ;;
    --quiet | -q)
      DOCKER_EXTRA_ARGS="${DOCKER_EXTRA_ARGS} -q"
      ASH_ARGS="${ASH_ARGS} --quiet"
      ;;
    --oci-runner | -o)
      shift
      OCI_RUNNER="$1"
      ;;
    --no-build)
      NO_BUILD="YES"
      ;;
    --no-run)
      NO_RUN="YES"
      ;;
    --debug)
      DEBUG="YES"
      ;;
    --help | -h)
      source "${ASH_ROOT_DIR}/ash-multi" --help
      exit 0
      ;;
    --version | -v)
      source "${ASH_ROOT_DIR}/ash-multi" --version
      exit 0
      ;;
    --finch | -f)
      # Show colored deprecation warning from entrypoint script and exit 1
      source "${ASH_ROOT_DIR}/ash-multi" --finch
      exit 1
      ;;
    *)
      ASH_ARGS="${ASH_ARGS} $1"
  esac
  shift
done

# Default to the pwd
if [ "${SOURCE_DIR}" = "" ]; then
  SOURCE_DIR="$(pwd)"
fi

# Resolve the absolute paths
SOURCE_DIR="$(cd "$SOURCE_DIR"; pwd)"
if [[ "${OUTPUT_DIR_SPECIFIED}" == "YES" ]]; then
  mkdir -p "${OUTPUT_DIR}"
  OUTPUT_DIR="$(cd "$OUTPUT_DIR"; pwd)"
fi

#
# Gather the UID and GID of the caller
#
# HOST_UID=$(id -u)
# HOST_GID=$(id -g)

# Resolve the OCI_RUNNER
RESOLVED_OCI_RUNNER=${OCI_RUNNER:-$(command -v finch || command -v docker || command -v nerdctl || command -v podman)}

# If we couldn't resolve an OCI_RUNNER, exit
if [[ "${RESOLVED_OCI_RUNNER}" == "" ]]; then
    echo "Unable to resolve an OCI_RUNNER -- exiting"
    exit 1
# else, build and run the image
else
    if [[ "${DEBUG}" = "YES" ]]; then
      set -x
    fi
    echo "Resolved OCI_RUNNER to: ${RESOLVED_OCI_RUNNER}"

    # Build the image if the --no-build flag is not set
    if [ "${NO_BUILD}" = "NO" ]; then
      echo "Building image ${ASH_IMAGE_NAME} -- this may take a few minutes during the first build..."
      ${RESOLVED_OCI_RUNNER} build \
        --tag ${ASH_IMAGE_NAME} \
        --file "${ASH_ROOT_DIR}/Dockerfile" \
        ${DOCKER_EXTRA_ARGS} \
        "${ASH_ROOT_DIR}"
        # --build-arg UID="${HOST_UID}" \
        # --build-arg GID="${HOST_GID}" \
      # eval $build_cmd
    fi

    # Run the image if the --no-run flag is not set
    RC=0
    if [ "${NO_RUN}" = "NO" ]; then
      MOUNT_SOURCE_DIR="--mount type=bind,source=${SOURCE_DIR},destination=/src"
      MOUNT_OUTPUT_DIR=""
      OUTPUT_DIR_OPTION=""
      if [[ ${OUTPUT_DIR_SPECIFIED} = "YES" ]]; then
        MOUNT_SOURCE_DIR="${MOUNT_SOURCE_DIR},readonly" # add readonly source mount when --output-dir is specified
        MOUNT_OUTPUT_DIR="--mount type=bind,source=${OUTPUT_DIR},destination=/out"
        OUTPUT_DIR_OPTION="--output-dir /out"
      fi
      echo "Running ASH scan using built image..."
      ${RESOLVED_OCI_RUNNER} run \
        --rm \
        -e ACTUAL_SOURCE_DIR="${SOURCE_DIR}" \
        -e ASH_DEBUG=${DEBUG} \
        ${MOUNT_SOURCE_DIR} \
        ${MOUNT_OUTPUT_DIR} \
        ${ASH_IMAGE_NAME} \
          ash \
            --source-dir /src  \
            ${OUTPUT_DIR_OPTION}  \
            $ASH_ARGS
      RC=$?
    fi
    if [[ "${DEBUG}" = "YES" ]]; then
      set +x
    fi
    exit ${RC}
fi
