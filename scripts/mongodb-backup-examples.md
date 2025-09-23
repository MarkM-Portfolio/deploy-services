# Backup and restore approaches:

## Example using AWS Snapshots and recreating Replica Set
>note: This is a good approach as we are not limited to the size of the DB, like we'd be using mongodump / mongorestore

1 - Create the files
mongo-persistent-storage-mongo-0.yaml:
```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  annotations:
    volume.beta.kubernetes.io/storage-provisioner: kubernetes.io/aws-ebs
  labels:
    app: mongo
    mService: mongodb
    role: mongo-rs
  name: mongo-persistent-storage-mongo-0
  namespace: connections
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  volumeName: pvc-5cc7c27b-96d5-11e7-9c44-060ec9af41c8
status:
  accessModes:
  - ReadWriteOnce
  capacity:
    storage: 100Gi
```
>note: Use `uuidgen` command to generate the volumeName above


pv_pvc-5cc7c27b-96d5-11e7-9c44-060ec9af41c8.yaml:
```
apiVersion: v1
kind: PersistentVolume
metadata:
  labels:
    failure-domain.beta.kubernetes.io/region: us-east-1
    failure-domain.beta.kubernetes.io/zone: us-east-1b
  name: pvc-5cc7c27b-96d5-11e7-9c44-060ec9af41c8
spec:
  accessModes:
  - ReadWriteOnce
  awsElasticBlockStore:
    fsType: ext4
    volumeID: aws://us-east-1b/vol-08781cda2e0ec5b1b
  capacity:
    storage: 100Gi
  claimRef:
    apiVersion: v1
    kind: PersistentVolumeClaim
    name: mongo-persistent-storage-mongo-0
    namespace: connections
  persistentVolumeReclaimPolicy: Delete
```

2 - Create a snapshot of one of the mongo demons of the ReplicaSet we want to backup:
> As this is a ReplicaSet, we have to backup only one instance

Find the volumeID:
```
kubectl get pvc,pv -n default | grep mongo-0
pvc/mongo-persistent-storage-mongo-0   Bound     pvc-c80efeeb-08a7-11e7-93d7-060ec9af41c8   100Gi      RWO           181d

pv/pvc-c80efeeb-08a7-11e7-93d7-060ec9af41c8   100Gi      RWO           Delete          Bound     default/mongo-persistent-storage-mongo-0                 181d

kubectl describe pv pvc-c80efeeb-08a7-11e7-93d7-060ec9af41c8 | grep VolumeID
    VolumeID:   aws://us-east-1b/vol-006411bcb935c07aa
```

3 - Create a snapshot of the volume:
```
aws ec2 create-snapshot --volume-id vol-006411bcb935c07aa --description "mongo-0 PV snapshot (db migration)"
```
Result:
```
{
    "Description": "mongo-0 PV snapshot (db migration)",
    "Encrypted": false,
    "VolumeId": "vol-006411bcb935c07aa",
    "State": "pending",
    "VolumeSize": 100,
    "Progress": "",
    "StartTime": "2017-09-07T12:21:49.000Z",
    "SnapshotId": "snap-04f4ec751a205723d",
    "OwnerId": "905409959051"
}
```

4 - Create a volume with this snapshot (note, it should be in the same AvailabilityZone of the current Volume to be replaced - mongo-0 of `connections NS`)
```
/usr/local/bin/aws ec2 create-volume \
--snapshot-id snap-04f4ec751a205723d \
--region us-east-1 \
--availability-zone us-east-1b \
--volume-type gp2 \
--size 8
```
result:
```
{
    "AvailabilityZone": "us-east-1b",
    "Encrypted": false,
    "VolumeType": "gp2",
    "VolumeId": "vol-07b2c1519a15315f6",
    "State": "creating",
    "Iops": 300,
    "SnapshotId": "snap-04f4ec751a205723d",
    "CreateTime": "2017-09-11T13:49:50.245Z",
    "Size": 100
}
```
*obs:* Change the volumeID in the file pv_pvc-5cc7c27b-96d5-11e7-9c44-060ec9af41c8.yaml with the created one above.

5 - Create the PV and PVC using the files of the step 1:
```
kubectl create -f pv_pvc-5cc7c27b-96d5-11e7-9c44-060ec9af41c8.yaml
kubectl create -f mongo-persistent-storage-mongo-0.yaml
```

6 - Check if they got bound:
```
kubectl get pvc,pv -n connections | grep mongo-0
pvc/mongo-persistent-storage-mongo-0   Bound     pvc-5cc7c27b-96d5-11e7-9c44-060ec9af41c8   100Gi      RWO           1m

pv/pvc-5cc7c27b-96d5-11e7-9c44-060ec9af41c8   100Gi      RWO           Delete          Bound     connections/mongo-persistent-storage-mongo-0             1m
```

7 - Deploy mongodb under `connections` namespace and wait until all pods get the status `running`
```
kubectl get pods -n connections | grep mongo
mongo-0                                  2/2       Running             0          19m
mongo-1                                  2/2       Running             0          18m
mongo-2                                  2/2       Running             0          18m
```

8 - As the migrated data comes from another namespace, the RS is broken. We have to reset it manually in order mongodb-sidecar can recovery automatically:

 - Attach to the mongo-0 container and start a mongo client instance:
 ```
 kubectl exec -it mongo-0 -c mongo -n connections bash
 mongo
 ```

 - Reset RS in order mongodb-sidecar can get it reconfigured:
 ```
 rs0:OTHER> cfg = rs.conf()
 rs0:OTHER> cfg.members[0].host = "mongo-0.mongo.connections.svc.cluster.local:27017"
 rs0:OTHER> cfg.members = [cfg.members[0]]
 rs0:OTHER> rs.reconfig(cfg, {force : true})
 ```
 Final result:
 ```
 { "ok" : 1 }
 ```

9 - After some seconds, you will be able to see the RS health again by performing:
```
kubectl exec -n connections -it mongo-0 -c mongo -- mongo mongo-2.mongo:27017 --eval "rs.status()" | grep "id\|name\|health\|stateStr\|ok"
                        "_id" : 41,
                        "name" : "mongo-0.mongo.connections.svc.cluster.local:27017",
                        "health" : 1,
                        "stateStr" : "PRIMARY",
                        "_id" : 42,
                        "name" : "mongo-1.mongo.connections.svc.cluster.local:27017",
                        "health" : 1,
                        "stateStr" : "SECONDARY",
                        "_id" : 43,
                        "name" : "mongo-2.mongo.connections.svc.cluster.local:27017",
                        "health" : 1,
                        "stateStr" : "SECONDARY",
        "ok" : 1
```

10 - Check if the data was migrated successfully:
```
kubectl exec -it mongo-0 -c mongo -n connections bash
mongo
show databases
admin    0.000GB
catalog  0.001GB
local    0.098GB
rs0:PRIMARY> use catalog
switched to db catalog
rs0:PRIMARY> show collections
AppDetail
AppDetail_nls
AppSecrets
Apps
Apps_nls
ConfigOptions
DbVersion
Extensions
MyApps
```

---

## Example using: mongodump / mongorestore:

### Case: Backup a database from a ReplicaSet with X.509 Auths activated and restore to a ReplicaSet with no X509 activated.
>note: Backuping from `default` namespace to a implementation under `connections` namespace

1 - Attash to the container and create the directory where the backup will be created:
```
kubectl exec -it mongo-0 -c mongo bash
mkdir -p /data/db/backups/catalog-bkp1
```
>note: the directory should be inside the PV, thus you can copy it aftwards from outside the container.

2 - Connect to a mongo demon:
```
mongo --ssl --host mongo-0.mongo.default.svc.cluster.local \
--sslPEMKeyFile /etc/mongodb/x509/user_admin.pem \
--sslCAFile /etc/mongodb/x509/mongo-CA-cert.crt \
--username 'C=IE,ST=Ireland,L=Dublin,O=IBM,OU=Connections-Middleware-Clients,CN=admin,emailAddress=admin@mongodb' \
--authenticationDatabase '$external' \
--authenticationMechanism=MONGODB-X509
```

3 - Lock the data sync:
```
use admin
db.fsyncLock()
```

4 - Backup the database:
```
mongodump --ssl --host mongo-0.mongo.default.svc.cluster.local \
--sslPEMKeyFile /etc/mongodb/x509/user_admin.pem \
--sslCAFile /etc/mongodb/x509/mongo-CA-cert.crt \
--authenticationDatabase '$external' \
--username 'C=IE,ST=Ireland,L=Dublin,O=IBM,OU=Connections-Middleware-Clients,CN=admin,emailAddress=admin@mongodb' \
--authenticationMechanism=MONGODB-X509 \
--db catalog \
--out /data/db/backups/catalog-bkp1
```

5 - Connect to the deamon again (perform step 2), and unlock the datasync:
```
use admin
db.fsyncUnlock()
```

6 - Migrate the backup to the Volume where you want to restore it. Eg:
```
cp -rf /pv/mongo-node-0/data/db/backups/catalog-bkp1 /pv-connections/mongo-node-0/data/db/
```

7 - Attash to the container of the target mongo Replica Set:
```
kubectl exec -n connections -it mongo-0 -c mongo bash
```

8 - Restore the database:
```
mongorestore --host mongo-0.mongo.connections.svc.cluster.local --db catalog /data/db/catalog-bkp1/catalog
```

10 - Check the data

---

# MongoDB: Approaches of data migration
## From hybridcloud_603 to CR1

### Latest 603 version: hybridcloud_603/hybridcloud_20170825-110759.zip
**Env:**
```
upgradepink-master.swg.usma.ibm.com
hybridcloud_603/hybridcloud_20170825-110759.zip
```

### Latest version:
**Env:**
```
starterpack-master.swg.usma.ibm.com
hybridcloud_20171005-070831.zip
```

1 - Document the creation of 3 new directories to receive the new PVs
 - https://www.ibm.com/support/knowledgecenter/SSYGQH_6.0.0/admin/install/r_Orient_Me_setup_pers_vols.html
 - Update fullPVs_NFS and fullPVs_HostPath instructions
3 - Doc 2 migration examples:
 - A) Using mongodump/mongorestore
 - B) Using Volume snapshot / ReplicaSet recreation

# Approach A

>Note: For all steps that demands connecting to a POD, be sure you're in the PRIMARY ONE.
You can check it by performing:

```
kubectl exec -it mongo-0 -c mongo -n default -- mongo mongo-2.mongo:27017 --eval "rs.status()" | grep "id\|name\|health\|stateStr\|ok"
                        "_id" : 0,
                        "name" : "mongo-0.mongo.connections.svc.cluster.local:27017",
                        "health" : 1,
                        "stateStr" : "SECONDARY",
                        "_id" : 1,
                        "name" : "mongo-1.mongo.connections.svc.cluster.local:27017",
                        "health" : 1,
                        "stateStr" : "PRIMARY",
                        "_id" : 2,
                        "name" : "mongo-2.mongo.connections.svc.cluster.local:27017",
                        "health" : 1,
                        "stateStr" : "SECONDARY",
        "ok" : 1
```
> Note - Change the `-n default` with the appropriate namespace of your Environment. Eg.: `-n connections`

1 - Environment with latest 603 deploy
```
upgradepink-master.swg.usma.ibm.com
hybridcloud_603/hybridcloud_20170825-110759.zip
```

2 - Generate Data Sample
```
[root@UpgradePink-master ~]# kubectl exec -it mongo-0 -c mongo bash
[root@mongo-0 /]# mongo
(...)
rs0:PRIMARY> use dbMigration
(...)
db.test.insert({ _id: 1, data: "abc1" })
db.test.insert({ _id: 2, data: "abc2" })
(...)
```
> note: If you face the error below when you perform commands after `mongo` command,
Is because your instance it's not the master one. So, atash to another POD or
say to mongo this is a safe procedure by performing first: `rs.slaveOk()`
```
rs0:SECONDARY> show databases
2017-10-09T09:20:30.655+0000 E QUERY    [main] Error: listDatabases failed:{
        "ok" : 0,
        "errmsg" : "not master and slaveOk=false",
        "code" : 13435,
        "codeName" : "NotMasterNoSlaveOk"
}
```

3 - Lock the data sync:
```
[root@UpgradePink-master ~]# kubectl exec -it mongo-0 -c mongo bash
[root@mongo-0 /]# mongo
(...)
rs0:PRIMARY> use admin
switched to db admin
rs0:PRIMARY> db.fsyncLock()
{
        "info" : "now locked against writes, use db.fsyncUnlock() to unlock",
        "lockCount" : NumberLong(1),
        "seeAlso" : "http://dochub.mongodb.org/core/fsynccommand",
        "ok" : 1
}
```
> Note: in this momment we are in a outage. MongoDB will not accept connections

4 - Backup the databases:
```
[root@mongo-0 /]# mongodump --host mongo-0.mongo.default.svc.cluster.local \
--archive=/data/db/mongodb-hybridcloud_603.gz --gzip
```

5 - Connect to the daemon again (perform step 2), and unlock the datasync:
```
[root@UpgradePink-master ~]# kubectl exec -it mongo-0 -c mongo bash
[root@mongo-0 /]# mongo
(...)
rs0:PRIMARY> use admin
switched to db admin
rs0:PRIMARY> db.fsyncUnlock()
{ "info" : "fsyncUnlock completed", "lockCount" : NumberLong(0), "ok" : 1 }
```

6 - Migrate the backup to the Volume where you want to restore it. Eg:
```
[root@UpgradePink-master db]# ssh root@starterpack-master.swg.usma.ibm.com
scp root@upgradepink-master.swg.usma.ibm.com:/pv/mongo-node-0/data/db/mongodb-hybridcloud_603.gz /pv/mongo-node-0/data/db/
```

7 - Restore the database:

- Perform the restore command:
```
[root@starterpack-master ~]# kubectl exec -n connections -it mongo-0 -c mongo bash
bash-4.3# mongorestore --host mongo-0.mongo.connections.svc.cluster.local \
--archive=/data/db/mongodb-hybridcloud_603.gz --gzip \
--nsExclude 'admin.*'
```

8 - Check the data
```
[root@starterpack-master ~]# kubectl exec -n connections -it mongo-1 -c mongo bash
bash-4.3# mongo
(...)
rs0:PRIMARY> show databases
AppReg          0.000GB
admin           0.000GB
collabscoredb   0.000GB
dbMigration     0.000GB
local           0.000GB
profiledb       0.000GB
relationshipdb  0.000GB
test            0.000GB
rs0:PRIMARY> use dbMigration
switched to db dbMigration
rs0:PRIMARY> show collections
test
rs0:PRIMARY> db.test.find()
{ "_id" : 1, "data" : "abc1" }
{ "_id" : 2, "data" : "abc2" }
{ "_id" : 3, "data" : "abc3" }
{ "_id" : 4, "data" : "abc4" }
```
