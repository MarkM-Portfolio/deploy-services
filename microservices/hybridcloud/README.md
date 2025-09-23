# Installing the IBM Connections Orient Me homepage

Follow the instructions in the linked document below to install and configure the IBM Connections Orient Me home page to get a cognitive view of your most essential Connections content.

 * https://www.ibm.com/support/knowledgecenter/SSYGQH_6.0.0/admin/install/c_install_orient_me_homepage.html

---

# Encryption at Rest

## MongoDB

As described at [[MongoDB][CfC][OnPrem][Cloud] Research about which approach take regarding Encrypt Data at rest #4426](https://github.ibm.com/connections/connections-planning/issues/4426), this is the documentation which covers the first implementation of Encryption at Rest.

### [Solution 1 - LUKS-crypt / mount at node level](https://github.ibm.com/connections/connections-planning/issues/4426)

 - Install cryptsetup
 ```
 yum install cryptsetup
 ```

 - Create the Virtual Block Devices (`count=1024` means the drive will have 1G)
 ```
 mkdir -p /pv/mongo-node-{0,1,2}/data/db/luks-crypt
 dd if=/dev/zero of=/pv/mongo-node-0/data/db/luks-crypt/dev0-backstore bs=1M count=1024
 dd if=/dev/zero of=/pv/mongo-node-1/data/db/luks-crypt/dev0-backstore bs=1M count=1024
 dd if=/dev/zero of=/pv/mongo-node-2/data/db/luks-crypt/dev0-backstore bs=1M count=1024
 ```

 - create the loopback block device and associate with the Virtual Block Device
 > Note: `7` is the major number of loop device driver. Check this number by performing: `grep loop /proc/devices`

 ```
 mknod /pv/mongo-node-0/data/db/luks-crypt/dev0-loopback b 7 1024
 mknod /pv/mongo-node-1/data/db/luks-crypt/dev0-loopback b 7 1024
 mknod /pv/mongo-node-2/data/db/luks-crypt/dev0-loopback b 7 1024
 losetup /pv/mongo-node-0/data/db/luks-crypt/dev0-loopback /pv/mongo-node-0/data/db/luks-crypt/dev0-backstore
 losetup /pv/mongo-node-1/data/db/luks-crypt/dev0-loopback /pv/mongo-node-1/data/db/luks-crypt/dev0-backstore
 losetup /pv/mongo-node-2/data/db/luks-crypt/dev0-loopback /pv/mongo-node-2/data/db/luks-crypt/dev0-backstore
 ```

 - For the next steps, you'll need a passphrase. It's important to keep safely, as once you lose this passphrase you loose your data. You can use a plain text for that, **but this this is discouraged**. In our example, we are going to generate a key with 32 bits (please, also consider having a different key for each drive):
 ```
 openssl rand -base64 32 > /path/to/safely/backup-place/mongo-volumes.key
 sudo chmod 0400 /path/to/safely/backup-place/mongo-volumes.key
 PASSPHRASE=$(cat /path/to/safely/backup-place/mongo-volumes.key)
 ```

 - Let's encrypt the data using our passphrase/key:
 ```
 echo -n $PASSPHRASE | cryptsetup -v -q luksFormat /pv/mongo-node-0/data/db/luks-crypt/dev0-backstore -
 echo -n $PASSPHRASE | cryptsetup -v -q luksFormat /pv/mongo-node-1/data/db/luks-crypt/dev0-backstore -
 echo -n $PASSPHRASE | cryptsetup -v -q luksFormat /pv/mongo-node-2/data/db/luks-crypt/dev0-backstore -
 ```

 - Let's initialize the volume:
 ```
 echo -n $PASSPHRASE | cryptsetup luksOpen /pv/mongo-node-0/data/db/luks-crypt/dev0-backstore mongo-0
 echo -n $PASSPHRASE | cryptsetup luksOpen /pv/mongo-node-1/data/db/luks-crypt/dev0-backstore mongo-1
 echo -n $PASSPHRASE | cryptsetup luksOpen /pv/mongo-node-2/data/db/luks-crypt/dev0-backstore mongo-2
 ```

 - Here's some checks you can perform to ensure that:
  dev/mapper/mongo-* was successfully created after luksFormat command:
  ```
  ls -l /dev/mapper/mongo-*
  ```

  Status of the mapping:
  ```
  cryptsetup -v status mongo-0
  cryptsetup -v status mongo-1
  cryptsetup -v status mongo-2
  ```

  Dump LUKS headers:
  ```
  cryptsetup luksDump /pv/mongo-node-0/data/db/luks-crypt/dev0-backstore
  cryptsetup luksDump /pv/mongo-node-1/data/db/luks-crypt/dev0-backstore
  cryptsetup luksDump /pv/mongo-node-2/data/db/luks-crypt/dev0-backstore
  ```

 - Let's create the filesystem at the initialized volume:
 ```
 mkfs.ext4 /dev/mapper/mongo-0
 mkfs.ext4 /dev/mapper/mongo-1
 mkfs.ext4 /dev/mapper/mongo-2
 ```

 - And finally mount the drive to the address of our NFS path:
 ```
 mount /dev/mapper/mongo-0 /pv/mongo-node-0/data/db
 mount /dev/mapper/mongo-1 /pv/mongo-node-1/data/db
 mount /dev/mapper/mongo-2 /pv/mongo-node-2/data/db
 ```

 - You can check the mounted drive by:
 ```
 df -h | grep mongo
 ```

From here you already can go ahead with the installation / Start of MongoDB, but if you're node was restarted, the drive mount will be lost, therefore let's ensure it will be remounted if it happens:

 - Get the UUID of your partitions:
 ```
 LINKS=$(ls -l /dev/mapper/ | grep mongo | awk '{split($0,a,"/");print a[2]}')
 LINKS=$(for i in $LINKS ; do  printf "$i\|"; done)
 LINKS=${LINKS::-2}
 ls -l /dev/disk/by-uuid | grep $LINKS
 ```

 - Add them to the `/etc/crypttab`. Eg.:
 ```
 echo "mongo-0 /dev/mapper/mongo-0 /path/to/safely/backup-place/mongo-volumes.key luks" >> /etc/crypttab
 echo "mongo-1 /dev/mapper/mongo-1 /path/to/safely/backup-place/mongo-volumes.key luks" >> /etc/crypttab
 echo "mongo-2 /dev/mapper/mongo-2 /path/to/safely/backup-place/mongo-volumes.key luks" >> /etc/crypttab
 ```

 - Specify the automount:
 ```
 echo "/dev/mapper/mongo-0 /pv/mongo-node-0/data/db auto" >> /etc/fstab
 echo "/dev/mapper/mongo-1 /pv/mongo-node-1/data/db auto" >> /etc/fstab
 echo "/dev/mapper/mongo-2 /pv/mongo-node-2/data/db auto" >> /etc/fstab
 ```

 - Mount them:
 ```
 mount -a
 ```
