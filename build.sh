#!/bin/bash
set -e

# Example Usage:
#      build.sh -t centos72-ansible-master -s 4096
#      build.sh -t centos72-ansible-master -s 4096 -d
#      build.sh -t centos72-ansible-master -s 4096 -u mys3bucket
#
# Running build.sh without any arguments will show the help

# Future Usage:
#      build.sh -t centos72-ansible-master -s 4096 -u mys3bucket -e ec2-ami-name
# 
EXIT_CODE=0

# Functions to display usage.
usage(){
    echo ""
    echo " Usage:"
    echo "        $0 [-a] [-c] [-d] [-n] [-h] [-r] [-s SIZE] [-t TEMPLATE ] [-u BUCKET]"
    echo ""
    echo " Parameters: (required)"
    echo "        -s SIZE              Will build the template with this size. In MB, 1024 MB == 1 GB."
    echo "        -t TEMPLATE          Will build the specified template. [Cannot be used in combination with -a]"
    echo ""
    echo " Options:"
    echo "        -c                   Will remove cached iso."
    echo "        -d                   Will show debug info."
    echo "        -n                   Will disable headless build"
    echo "        -h                   Will show this."
    echo "        -r                   Will remove qcow on finish."
    echo "        -u BUCKET            Will upload the template to the specified S3 bucket when build successfull."
    echo ""
    exit 1
}

# Show usage if no options are given.
if [ $# == 0 ]; then
    usage
fi

# Set all options to false.
DISK_SIZE=0
REMOVE_CACHE=0
UPLOAD_S3=0
S3_BUCKET=0
BUILD_TEMPLATE=0
BUILD_TEMPLATE_NAME=0
BUILD_ALL=0
DEBUG=0
PACKER_DBG=''
HEADLESS=1

# Loop over all arguments.
while getopts ":s:u:t:acdrnh" OPT; do
    case $OPT in
    c)
        REMOVE_CACHE=1
        ;;
    d)
        DEBUG=1
        PACKER_DBG='-debug'
        ;;
    n)
        HEADLESS=0
        ;;
    h)
        usage
        ;;
    r)
        REMOVE_QCOW=1
        ;;
    s)
        DISK_SIZE=$OPTARG
        ;;
    t)
        BUILD_TEMPLATE=1
        BUILD_TEMPLATE_NAME=$OPTARG
        ;;
    u)
        UPLOAD_S3=1
        S3_BUCKET=$OPTARG
        ;;
    \?)
        usage
        ;;
    esac
done


# If disk size is equal to zero, show usage.
if [ $DISK_SIZE -eq 0 ]; then
    echo "Error: Must define disk size."
    usage
fi

# DEBUG
if [ $DEBUG -eq 1 ]; then
    echo ""
    echo "DEBUG: DISK_SIZE: $DISK_SIZE"
    echo "DEBUG: REMOVE_CACHE: $REMOVE_CACHE"
    echo "DEBUG: REMOVE_QCOW: $REMOVE_QCOW"
    echo "DEBUG: HEADLESS: $HEADLESS"
    echo "DEBUG: UPLOAD_S3: $UPLOAD_S3"
    echo "DEBUG: S3_BUCKET: $S3_BUCKET"
    echo "DEBUG: BUILD_TEMPLATE: $BUILD_TEMPLATE"
    echo "DEBUG: BUILD_TEMPLATE_NAME: $BUILD_TEMPLATE_NAME"
    echo ""
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"

if hash packer.io 2>/dev/null; then
    PACKER=$(which packer.io)
elif hash packer 2>/dev/null; then
    PACKER=$(which packer)
else
    echo "ERROR:  Packer Not Found in PATH"
    exit 1
fi

if [ -z "$PACKER" ]; then
    echo "Error: Packer could not be found in PATH!"
    exit 1
fi

# Export environment variable GOMAXPROCS
export GOMAXPROCS=`nproc`

# Functions to build template
build_template(){
    START_MIN=$(date +%s)

    # First argument passed to build_template is the name.
    local TEMPLATE_NAME=$1
    local TEMPLATE_DIR_DISPLAY="${TEMPLATE_NAME}"
    local RETURN_CODE=0

    echo "Info: Entering directory ${TEMPLATE_NAME}"
    cd "${TEMPLATE_NAME}"

    if [ -d "packer_output" ]; then
        echo "Info: Folder packer_output exists. Removing folder."
        rm -fr packer_output
    fi

    echo "Info: Generating meta.data file."
    ../scripts/gen-metadata.sh ./${TEMPLATE_NAME}-meta.data

    echo "Info: Starting Packer.IO build of ${TEMPLATE_NAME}/template.json."
    ${PACKER} build \
        ${PACKER_DBG} \
        -var "disk_size=$DISK_SIZE" \
        -var "ncpu=$GOMAXPROCS" \
        -var "template_name=$TEMPLATE_NAME" \
        -var "headless=$HEADLESS" \
        template.json

    if [ ! $? -eq 0 ]; then
        echo "Error: Packer.IO build unsuccesfull, stopping."
        RETURN_CODE=1
    fi

    if [ $UPLOAD_S3 -eq 1 ]; then
        echo "Info: Uploading template $TEMPLATE_NAME.qcow2 to S3 bucket s3://$S3_BUCKET."
        aws s3 cp output-ansible-master/centos7-ec2-ansible-master.ova  s3://${S3_BUCKET}/centos7-ec2-ext4.ova
        # s3cmd put $TEMPLATE_NAME.qcow2 s3://$S3_BUCKET -P
    fi
    

    ## Uploading to S3
    # aws s3 cp output-ext4/centos7-ec2-ext4.ova s3://my-ami-bucket/centos7-ec2-ext4.ova

    ## Importing to EC2
    #  aws ec2 import-image --cli-input-json '{  "Description": "CentOS 7 EXT4", "DiskContainers": [ { "Description": "CentOS 7 EXT4", "UserBucket": { "S3Bucket": "my-ami-bucket", "S3Key" : "centos7-ec2-ext4.ova" } } ]}'


    if [ -d "packer_output" ]; then
        echo "Info: Removing temporary folder packer_output"
        rm -fr packer_output
    fi

    if [ $REMOVE_CACHE -eq 1 ]; then
        if [ -d "packer_cache" ]; then
            echo "Info: Removing cached iso and folder packer_cache."
            rm -rf packer_cache
        fi
    fi

    END_MIN=$(date +%s)
    DIFF_MIN=$(expr $(echo "$END_MIN - $START_MIN" | bc) / 60)
    echo "Info: Time to build template $TEMPLATE_NAME: $DIFF_MIN minutes."

    return $RETURN_CODE
}


if [ -f "$BUILD_TEMPLATE_NAME/template.json" ]; then
    echo "Info: Building template $BUILD_TEMPLATE_NAME"
    build_template $BUILD_TEMPLATE_NAME

    if [ "$?" -ne 0 ]; then
        echo "Error: Failed to build $BUILD_TEMPLATE_NAME"
        EXIT_CODE=1
    fi

else
    echo "Error: Template $BUILD_TEMPLATE_NAME doesn't exist!"
    EXIT_CODE=1
fi

exit $EXIT_CODE
