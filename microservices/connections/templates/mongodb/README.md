## MongoDB Replica Set deployment instruction

 > Note: Instructions below are to aim creating the automation pipeline in Jenkins. It's still in progress.

 - Download the YML files of this directory (microservices/connections/templates/mongodb)

 - Perform the commands:

```
kubectl apply -f microservices/connections/templates/mongodb/service.yml
kubectl apply -f microservices/connections/templates/mongodb/StatefulSets.yml
```

 - Once all done, we can test:

Open a bash instance in one of the PODs. Eg.:
```
kubectl exec -ti mongo-2 bash
```

 - Perform the commands:

```
mongo --nodb
conn = new Mongo("rs0/mongo-0.mongo:27017,mongo-1.mongo:27017,mongo-2.mongo:27017");
db = conn.getDB("admin");
use testdb
db.dataTest.table1.insert({"val":1});
db.dataTest.table1.find()
```

The result should be something like:
```
[ibmuser@badubkube1 mongodb-statefuset]$ kubectl exec -ti mongo-2 bash
Defaulting container name to mongo.
Use 'kubectl describe pod/mongo-2' to see all of the containers in this pod.
[root@mongo-2 /]# mongo --nodb
MongoDB shell version v3.4.0
> conn = new Mongo("rs0/mongo-0.mongo:27017,mongo-1.mongo:27017,mongo-2.mongo:27017");
2017-02-14T16:46:45.139+0000 I NETWORK  [main] Starting new replica set monitor for rs0/mongo-0.mongo:27017,mongo-1.mongo:27017,mongo-2.mongo:27017
2017-02-14T16:46:45.143+0000 I NETWORK  [ReplicaSetMonitor-TaskExecutor-0] changing hosts to rs0/10.11.107.106:27017,10.11.3.113:27017,10.11.80.88:27017 from rs0/mongo-0.mongo:27017,mongo-1.mongo:27017,mongo-2.mongo:27017
connection to rs0/mongo-0.mongo:27017,mongo-1.mongo:27017,mongo-2.mongo:27017
> db = conn.getDB("admin");
admin
rs0:PRIMARY> use testdb
switched to db testdb
rs0:PRIMARY> db.dataTest.table1.insert({"val":1});
WriteResult({ "nInserted" : 1 })
rs0:PRIMARY> db.dataTest.table1.find()
{ "_id" : ObjectId("589857d9fd17511022ae016d"), "val" : 1 }
rs0:PRIMARY>
```
