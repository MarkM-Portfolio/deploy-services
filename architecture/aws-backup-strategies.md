# Story Ref.: (...) Backup/Restore strategy for open cloud envs. [#9257](https://github.ibm.com/connections/connections-planning/issues/9257)
Assigned: Bruno Ambrozio \<bambrozi@ie.ibm.com\>

The Research and Proof of Concept result in 2 possible strategies, having the second as the best approach.

 - ### ~~[Strategy 1 - Application level](#strategy1)~~
 - ### [Strategy 2 - Infrastructure level *(Recommended)*](#strategy2)
   - #### [Graphic representation](#strategy2Diagram)

</br>

# <a name="strategy1"></a>Strategy 1: Application level

## MongoDB CE options:

### Using mongodump/mongorestore:

#### High level steps:
 - Scale Replica Set up (Mongo daemon instance for backup with `hidden=true`)
 - After data replicated, lock writes with the command `db.fsyncLock()`
 - Perform the `mongodump` in order to create the backup
 - Push the backup file to AWS S3
    - Create rules to archive and purge at/from S3 > S3 IA > Glacier after a configured period.

#### N.B: 
 > - mongodump only captures the documents in the database. The resulting backup is space efficient, but mongorestore or mongod must rebuild the indexes after restoring data.
 > - Not recommended approach for production. Problems happen when performed against big DBs. Eg.: DB: `relationshipdb.*'` [[MongoDB] mongorestore bug: panic: send on closed channel #7557](https://github.ibm.com/connections/connections-planning/issues/7557)
 >  ```
 >  panic: send on closed channel
 >  goroutine 9 [running]:
 >  github.com/mongodb/mongo-tools/common/archive.(*RegularCollectionReceiver).Write(0xc420184a20, 0xc427a06010, 0xcb, 0x1000000, 0xc420152658, 0x1, 0x0)
 >           /home/buildozer/aports/community/mongodb-tools/src/mongo-tools-r3.4.4/.gopath/src/github.com/mongodb/mongo-tools/common/archive/demultiplexer.go:286 +0x69
 >   (...)
 > ```

### Back Up by Copying Underlying Data Files

#### High level steps:
 - Coppy (`tar.gz`) all content from `/data/db` of one of the replicas
 - Push to AWS S3
    - Create rules to archive and purge at/from S3 > S3 IA > Glacier after a configured period.

#### N.B: 
 > - As no snapshot was taken, data might get corrupted during the copy process.
 > - Backup file can be too big to be uploaded to S3 (high cost)

## Solr 

### Using Backup REST API

#### High level steps:

 - Trigger the backup: 
 ```
curl -k $CURL_EXTRA_ARGS "https://127.0.0.1:8984/solr/admin/collections?action=BACKUP&name=orient-me-collection_test&collection=orient-me-collection&location=/home/solr&async=reqID123"
 ```
 - Kepp monitoring the backup transaction till get done:
 ```
 curl -k $CURL_EXTRA_ARGS "https://127.0.0.1:8984/solr/admin/collections?action=REQUESTSTATUS&requestid=reqID123"
 ```
- Push backup file to AWS S3
  - Create rules to archive and purge at/from S3 > S3 IA > Glacier after a configured period.

#### N.B: 
 - Many issues was faced in a controled environment, just provisioned and integrated with PINK. Eg.: `orient-me-collection_shard1_replica3 because java.nio.file.NoSuchFileException: /home/solr/data/server/solr/orient-me-collection_shard1_replica3/data/index/segments_5`
 - Apparently the backup API fails every time the leaders are spread over multiple nodes, an workaround is:
    1. create backup folder on each node other than the one we call the URL against
    2. perform the REST API call
    3. aggregate the backup into 1 single folder at some shared backup location

# <a name="strategy2"></a>Strategy 2: AWS EBS Snapshots 
> AWS Lambda & S3 > S3 IA > Glacier

This strategy amis to backup any volume of Pink, agnostic of service. It will work for all MS's currently existent or new created.


#### <a name="strategy2Diagram"></a>Graphic representation


![image](https://media.github.ibm.com/user/15366/files/99868ea8-3cfa-11e8-877a-3cd677d66a9b)


#### High level steps:
 - Create an AWS IAM role eg.: `pink-backup-worker`
 - Building an IAM Policy
    - Write CloudWatch logs (to debug the functions).
    - Read EC2 information about instances (Volumes, snapshots an their tags (describes)).
    - Take new snapshots using the EC2:CreateSnapshot call.
    - Add tags (retained and timestamps to purged snapshots)
    - Delete EBS snapshots with expired tags

 - Create the Lambda Functions **(Python + boto3)**
    - Script 1: Backuper
        - List volumes by tag (eg: K8S PVC name is a tag created by StorageClasses when provising EBS Volumes)
        - Create snapshots of all them
        - Tag the snapshots 
            - with a expiration date (eg: `DeleteOn` tag in 7 days)
            - with K8s tags from the Volume (eg.: PVC name, AZ, etc)

    - Script 2: Purger
        - List and delete snapshots expired (eg.: tag `DeleteOn` <= today)

    - Script 3: Archiver
        - Create a volume with the latest snapshot of the day before of each microservice
        - Mount them in a EC2
        - TarGz of the whole content 
        - Push the TarGz to S3
        - Expirate all snapshots before the one pushed to S3 (eg.: put the `DeleteOn` tag date before current date)

 - Schedule the Lambda Functions
    - In the AWS Lambda management console, we can for example:
        - script 1(backuper): each hour
        - script 2(purger): every night
        - script 3(archiver S3): every morning

 - Configure S3 to (Examples:)
    - Send content to IA after `n` week
        - S3 =~ $0.023/GB, S3-IA =~ $0.0125/GB)
    - Send content form IA to Glacieer after `n` week
        - AWS Glacier =~ $0.004/GB

 - Configure Glacier
    - Purge content after `n` weeks
