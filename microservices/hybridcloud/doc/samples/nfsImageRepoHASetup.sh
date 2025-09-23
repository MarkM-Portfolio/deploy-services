#!/bin/bash

NFS_shares=("/CFC_IMAGE_REPO" "/CFC_AUDIT")

for dir in "${NFS_shares[@]}"
do
	echo "Creating the directory $dir"
	mkdir -p $dir
done

echo "Configuring NFS..."
touch /etc/exports #If not exist, will create it
cp -n /etc/exports /etc/exports.bkp
IFS='\.' read -a DEC_IP <<< "$(hostname -i)"
for dir in "${NFS_shares[@]}"
do
	echo "$dir        ${DEC_IP[0]}.${DEC_IP[1]}.0.0/255.255.0.0(rw,no_root_squash)" >> /etc/exports
done

# Enable and start resources for NFS
systemctl enable rpcbind
systemctl enable nfs-server
systemctl enable nfs-lock
systemctl enable nfs-idmap
systemctl start rpcbind
systemctl start nfs-server
systemctl start nfs-lock
systemctl start nfs-idmap

# Restart NFS server and configure the firewall
systemctl restart nfs-server
firewall-cmd --permanent --zone=public --add-service=nfs
firewall-cmd --reload

echo "NFS successfully configured!"

