##this should be in a separate file##
#!/bin/sh
#For connecting to the wsadmin scripting tool
WAS_HOME=/was9/IBM/WebSphere/AppServer
file=$1
${WAS_HOME}/bin/wsadmin.sh -conntype SOAP -host rohini -port 8879 -lang jython -f $file -username wasadmin -password sarasu10


###this should be in a separate file##

/wsadminConnector.sh jms.py
echo "JMS application has been deployed on the cluster $clusterName"

###########################################################################

#Bus Creation

echo "AdminTask.createSIBus('[-bus $busName -busSecurity true -scriptCompatibility 6.1 ]')" > busCreation.py
echo "AdminTask.getSecurityDomainForResource('[-resourceName SIBus=$busName -getEffectiveDomain false]')" >> busCreation.py
echo "AdminTask.modifySIBus('[-bus $busName -busSecurity true -permittedChains SSL_ENABLED ]')" >> busCreation.py
echo "AdminConfig.save()" >> busCreation.py
echo "AdminConfig.reset()" >> busCreation.py
echo "AdminTask.listSIBuses()" >> busCreation.py
./wsadminConnector.sh busCreation.py
echo "Bus has been created"

#Adding bus members
echo "AdminTask.addSIBusMember('[-bus $busName -cluster $clusterName -enableAssistance true -policyName HA -fileStore -logSize 100 -logDirectory $logDirectoryPath -minPermanentStoreSize 200 -maxPermanentStoreSize 500 -unlimitedPermanentStoreSize false -permanentStoreDirectory $permanentStoreDirectoryPath -minTemporaryStoreSize 200 -maxTemporaryStoreSize 500 -unlimitedTemporaryStoreSize false -temporaryStoreDirectory $temporaryStoreDirectory ]')" > busMembers.py
echo "AdminConfig.save()" >> busMembers.py
echo "AdminTask.listSIBusMembers('[-bus $busName ]')" >> busMembers.py
./wsadminConnector.sh busMembers.py
echo "Bus members has been added to the bus"

#Creating queue connection factory
echo "AdminTask.createSIBJMSConnectionFactory('$clusterName(cells/$cellName/clusters/$clusterName|cluster.xml)', '[-type queue -name $connectionFactoryName -jndiName $jndiName -description -category -busName $busName -nonPersistentMapping ExpressNonPersistent -readAhead Default -tempQueueNamePrefix -target -targetType BusMember -targetSignificance Preferred -targetTransportChain -providerEndPoints -connectionProximity Bus -authDataAlias -containerAuthAlias -mappingAlias -shareDataSourceWithCMP false -logMissingTransactionContext false -manageCachedHandles false -xaRecoveryAuthAlias -persistentMapping ReliablePersistent -consumerDoesNotModifyPayloadAfterGet false -producerDoesNotModifyPayloadAfterSet false]')" > jmsResource.py

#Creating queue
echo "AdminTask.createSIBJMSQueue('$clusterName(cells/$cellName/clusters/$clusterName|cluster.xml)', '[-name queue -jndiName $queueJNDI -description -deliveryMode Application -readAhead AsConnection -busName $busName -queueName _SYSTEM.Exception.Destination.cluster.000-$busName -scopeToLocalQP false -producerBind false -producerPreferLocal true -gatherMessages false]') " >> jmsResource.py
echo "AdminConfig.save()" >> jmsResource.py
echo "AdminConfig.reset()" >> jmsResource.py
./wsadminConnector.sh jmsResource.py
echo "Queue Connection Factory and Queue has been created"

###########################################################################

#J2C authentication
echo "AdminTask.createAuthDataEntry('[-alias DB2 -user $db2username -password $db2password -description "db2 configuration"]')" > j2Cauthentication.py
echo "AdminConfig.save()" >> j2Cauthentication.py
./wsadminConnector.sh j2Cauthentication.py
echo "Added db2 credentials in the J2C authentication"

#Creating JDBC provider
echo "AdminTask.createJDBCProvider('[-scope Cluster=$clusterName \
-databaseType DB2 \
-providerType \"DB2 Universal JDBC Driver Provider\" \
-implementationType \"Connection pool data source\" \
-name \"DB2 Universal JDBC Driver Provider\" \
-description \"One-phase commit DB2 JCC provider that supports JDBC 3.0. Data sources that use this provider support only 1-phase commit processing, unless you use driver type 2 with the application server for z/OS. If you use the application server for z/OS, driver type 2 uses RRS and supports 2-phase commit processing.\" \
-classpath [$db2jcc $db2jcc_license_cu] \
-nativePath [$nativePath] \
]')" > jdbcResource.py
echo "AdminConfig.save()" >> jdbcResource.py
./wsadminConnector.sh jdbcResource.py
echo "JDBC provider has been created"

#Adding JDBC resource
echo "print(AdminConfig.list('JDBCProvider', AdminConfig.getid( '/Cell:$cellName/ServerCluster:$clusterName/')))" > providerDetails.py
./wsadminConnector.sh providerDetails.py | grep "DB2 Universal JDBC Driver Provider" > providerDetails.txt
jdbc_provider=$(<providerDetails.txt)

echo "AdminTask.createDatasource('$jdbc_provider', '[-name dataSource -jndiName db2 -dataStoreHelperClassName com.ibm.websphere.rsadapter.DB2UniversalDataStoreHelper -containerManagedPersistence true -componentManagedAuthenticationAlias rohiniCellManager01/DB2 -configureResourceProperties [[databaseName java.lang.String $databaseName] [driverType java.lang.Integer 4] [serverName java.lang.String $dbHostName] [portNumber java.lang.Integer $dbPort]]]')" > dataSource.py
echo "AdminConfig.save()" >> dataSource.py
./wsadminConnector.sh dataSource.py
echo "Data source configuration has been successfully created"

###########################################################################







$WAS_HOME/profiles/AppSrv01/bin/stopNode.sh -username $username -password $password
$WAS_HOME/profiles/AppSrv02/bin/stopNode.sh -username $username -password $password
$WAS_HOME/profiles/AppSrv01/bin/syncNode.sh $hostname  8879 -username $username -password $password
$WAS_HOME/profiles/AppSrv02/bin/syncNode.sh $hostname  8879 -username $username -password $password
$WAS_HOME/profiles/Dmgr01/bin/stopManager.sh -username $username -password $password
$WAS_HOME/profiles/Dmgr01/bin/startManager.sh
$WAS_HOME/profiles/AppSrv01/bin/startNode.sh
$WAS_HOME/profiles/AppSrv02/bin/startNode.sh
