#!/bin/bash

# Define the size of the image
IMAGE_SIZE=32M
# Define the name of the image file
IMAGE_NAME="bootfs.ext4"
# Define the directory containing the files to include in the image
FILES_DIR="./boot"

# Create an empty file of the specified size
dd if=/dev/zero of=$IMAGE_NAME bs=1M count=32

# Format the file with a VFAT filesystem
mkfs.vfat $IMAGE_NAME

# Create a mount point
MOUNT_POINT="/mnt/bootfs"
sudo mkdir -p $MOUNT_POINT

# Mount the image
sudo mount -o loop $IMAGE_NAME $MOUNT_POINT

# Copy the files into the image
for item in $FILES_DIR/*; do
  if [ -d "$item" ]; then
    sudo cp -r "$item" $MOUNT_POINT/
  else
    sudo cp "$item" $MOUNT_POINT/
  fi
done

# Unmount the image
sudo umount $MOUNT_POINT

# Remove the temporary mount point
sudo rmdir $MOUNT_POINT

echo "Image $IMAGE_NAME created successfully with VFAT filesystem."
