#!/bin/sh

#set -x

# stop old containers, no containers should be running on this build machine
# First delete all stopped containers
echo "WARNING! This will remove all stopped containers..."
docker container prune --force
if [ $? -ne 0 ]; then
    # Failed to delete all stopped containers
    echo "Failed to delete all stopped containers!!!"
    exit 2
fi
echo "Deleted! all stopped containers."

# Then delete both dangling and unused images
echo "WARNING! This will remove all images without at least one container associated to them..."
docker image prune -a --force
if [ $? -ne 0 ]; then
    # Failed to delete both dangling and unused images
    echo "Failed to delete both dangling and unused images!!!"
    exit 2
fi
echo "Removed! all images not referenced by any container."

echo "Cleanup old images ..."
ref_timestamp=`date -d "4 hours ago" +%Y%m%d_%H%M%S`
echo "Remove docker images that tagged earlier than ${ref_timestamp}"
docker images | grep -E 'artifactory.*[0-9]{8}[_-][0-9]{4,6}' | while read line; do
    name=$(echo $line | awk '{print $1}')
    tag=$(echo $line | awk '{print $2}')
    id=$(echo $line | awk '{print $3}')
    #echo $name - $tag - $id
    # python True will exit 1, which is opposite of the shell if, so use 'not'
    tag=`python -c "print \"${tag}\".replace('-', '_')"`
    if python -c "exit(not \"${ref_timestamp}\" > \"${tag}\")" ; then
        echo "remove ${name}:${tag}"
        docker rmi --force $id
    else
        echo "${tag} not old enough, keep for a while."
    fi
done

# Remove all unused local volumes. Unused local volumes are those which are not referenced by any containers
echo "Remove all unused local volumes..."
echo "Unused local volumes are those which are not referenced by any containers..."
echo
echo "WARNING! This will remove all local volumes not used by at least one container..."
docker volume prune --force
if [ $? -ne 0 ]; then
    # Failed to remove all unused local volumes
    echo "Failed to remove all unused local volumes!!!"
    exit 2
fi
echo "Removed! all local volumes not used by at least one container."

echo 
echo "Clean Exit!"