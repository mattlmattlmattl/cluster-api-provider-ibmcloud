#!/bin/bash
set -e

# Function that prints out the help message, describing the script
print_help()
{
  echo "$SCRIPT - generates a provider-configs.yaml file"
  echo ""
  echo "Usage:"
  echo "$SCRIPT [options] <path/to/clouds.yaml> <provider os: [ubuntu]> [output folder]"
  echo "options:"
  echo "-h, --help                    show brief help"
  echo "-f, --force-overwrite         if file to be generated already exists, force script to overwrite it"
  echo ""
}

# Supported Operating Systems
declare -a arr=("ubuntu")
SCRIPT=$(basename $0)
while test $# -gt 0; do
        case "$1" in
          -h|--help)
            print_help
            exit 0
            ;;
          -f|--force-overwrite)
            OVERWRITE=1
            shift
            ;;
          *)
            break
            ;;
        esac
done

# Check if clouds.yaml file provided
if [[ -n "$1" ]] && [[ $1 != -* ]] && [[ $1 != --* ]];then
  CLOUDS_PATH="$1"
else
  echo "Error: No clouds.yaml provided"
  echo "You must provide a valid clouds.yaml"
  echo ""
  print_help
  exit 1
fi

# Check that OS is provided
if [[ -n "$2" ]] && [[ $2 != -* ]] && [[ $2 != --* ]]; then
  USER_OS=$(echo $2 | tr '[:upper:]' '[:lower:]')
else
  echo "Error: No provider OS specified"
  echo "You mush choose between the following operating systems: ubuntu"
  echo ""
  print_help
  exit 1
fi

OUTPUT=out
if [[ -n "$3" ]] && [[ $3 != -* ]] && [[ $3 != --* ]]; then
  OUTPUT=$(echo $3 | tr '[:upper:]' '[:lower:]')
else
  echo "no output folder provided, use name 'out' by default"
fi

# Check that OS is supported
for i in "${arr[@]}"
do
  if test "$USER_OS" = "$i"; then
    PROVIDER_OS=$i
    break
  fi
done

if test -z "$PROVIDER_OS"; then
  echo "provider-os error: $USER_OS is not one of the supported operating systems!"
  print_help
  exit 1
fi

if [ -e $OUTPUT/provider-components.yaml ] && [ "$OVERWRITE" != "1" ]; then
  echo "Can't overwrite provider-components.yaml without user permission. Either run the script again"
  echo "with -f or --force-overwrite, or delete the file in the out/ directory."
  echo ""
  print_help
  exit 1
fi


# Define global variables
PWD=$(cd `dirname $0`; pwd)
CONFIG_DIR=$PWD/provider-component/clouds-secrets/configs
OVERWRITE=${OVERWRITE:-0}
CLOUDS_PATH=${CLOUDS_PATH:-""}
USERDATA=$PWD/provider-component/user-data
MASTER_USER_DATA=$USERDATA/$PROVIDER_OS/templates/master-user-data.sh
WORKER_USER_DATA=$USERDATA/$PROVIDER_OS/templates/worker-user-data.sh

CLOUD_SSH_PRIVATE_FILE=id_ibmcloud
CLOUD_SSH_HOME=${HOME}/.ssh/
# Create ssh key to access IBM Cloud machines on demand
if [ ! -f ${CLOUD_SSH_HOME}${CLOUD_SSH_PRIVATE_FILE} ]; then
  echo "Generating SSH key files for IBM cloud machine access."
  # This is needed because GetKubeConfig assumes the key in the home .ssh dir.
  ssh-keygen -t rsa -f ${CLOUD_SSH_HOME}${CLOUD_SSH_PRIVATE_FILE}  -N ""
fi

# Prepare dependecies for kustomize
mkdir -p $CONFIG_DIR
cat $PWD/$CLOUDS_PATH > $CONFIG_DIR/clouds.yaml
cat "$MASTER_USER_DATA" > $USERDATA/$PROVIDER_OS/master-user-data.sh
cat "$WORKER_USER_DATA" > $USERDATA/$PROVIDER_OS/worker-user-data.sh

# Set up the output dir if it does not yet exist
mkdir -p $PWD/$OUTPUT
cp -n $PWD/cluster.yaml.template $PWD/$OUTPUT/cluster.yaml
cp -n $PWD/machines.yaml.template $PWD/$OUTPUT/machines.yaml

# Build provider-components.yaml with kustomize
kustomize build $PWD/../../../../config -o $PWD/$OUTPUT/provider-components.yaml

echo "---" >> $PWD/$OUTPUT/provider-components.yaml
kustomize build $PWD/provider-component/clouds-secrets >> $PWD/$OUTPUT/provider-components.yaml

echo "---" >> $PWD/$OUTPUT/provider-components.yaml
kustomize build $PWD/provider-component/cluster-api >> $PWD/$OUTPUT/provider-components.yaml

echo "---" >> $PWD/$OUTPUT/provider-components.yaml
kustomize build $USERDATA/$PROVIDER_OS >> $PWD/$OUTPUT/provider-components.yaml

