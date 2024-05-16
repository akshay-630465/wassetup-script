#!/bin/sh

WAS_HOME="/opt/IBM/WebSphere/AppServer"
##############creating dmgr and managed profiles#####################################

dmgr_name="was2"
manage_profile1="managed5"
manage_profile2="managed6"
adminuser_name="wasadmin"
admin_password="sarasu10"
host="192.168.2.155"

## Create dmgr profile
${WAS_HOME}/bin/manageprofiles.sh -create -profileName "$dmgr_name" -templatePath "${WAS_HOME}/profileTemplates/dmgr" -enableAdminSecurity true -adminUserName "$adminuser_name" -adminPassword "$admin_password" -hostName "$host"

## Start deployment manager
${WAS_HOME}/profiles/$dmgr_name/bin/startManager.sh

## Create managed profiles
${WAS_HOME}/bin/manageprofiles.sh -create -profileName "$manage_profile1" -templatePath "${WAS_HOME}/profileTemplates/managed" -enableAdminSecurity true -adminUserName "$adminuser_name" -adminPassword "$admin_password" -hostName "$host"

${WAS_HOME}/bin/manageprofiles.sh -create -profileName "$manage_profile2" -templatePath "${WAS_HOME}/profileTemplates/managed" -enableAdminSecurity true -adminUserName "$adminuser_name" -adminPassword "$admin_password" -hostName "$host"

# Extract SOAP connector port number from AboutThisProfile file
cd "${WAS_HOME}/profiles/$dmgr_name/logs" || exit
soap_port=$(grep -oP 'Management SOAP connector port: \K\d+' AboutThisProfile.txt)
echo "SOAP connector port number is: $soap_port"

#####################federation of nodes############################
## Add nodes
$WAS_HOME/profiles/$manage_profile1/bin/addNode.sh "$host" "$soap_port"
$WAS_HOME/profiles/$manage_profile2/bin/addNode.sh "$host" "$soap_port"
# Function to create server
create_server() {
    echo "AdminTask.createApplicationServer('$1', '[-name $2 -templateName default -genUniquePorts true ]')" > "$3"
    echo "AdminConfig.save()" >> "$3"
}

# Create servers
create_server "$NODE_NAME1" "server1" "create_server1.py"
create_server "$NODE_NAME2" "server2" "create_server2.py"

# Execute Jython script to create the servers
${WAS_HOME}/bin/wsadmin.sh -lang jython -conntype SOAP -host "$HOST" -port "$soap_port" -user "$adminuser_name" -password "$admin_password" -f create_server1.py
${WAS_HOME}/bin/wsadmin.sh -lang jython -conntype SOAP -host "$HOST" -port "$soap_port" -user "$adminuser_name" -password "$admin_password" -f create_server2.py

# Wait for server creation to complete
sleep 5

## Start nodes and servers
$WAS_HOME/profiles/$manage_profile1/bin/stopNode.sh
$WAS_HOME/profiles/$manage_profile1/bin/syncNode.sh "$HOST" "$soap_port"
$WAS_HOME/profiles/$manage_profile1/bin/startNode.sh
$WAS_HOME/profiles/$manage_profile1/bin/startServer.sh "server1"

$WAS_HOME/profiles/$manage_profile2/bin/stopNode.sh
$WAS_HOME/profiles/$manage_profile2/bin/syncNode.sh "$HOST" "$soap_port"
$WAS_HOME/profiles/$manage_profile2/bin/startNode.sh
$WAS_HOME/profiles/$manage_profile2/bin/startServer.sh "server2"

#############################################################################################################################

###############################creation of cluster####################################################################
## Create cluster

set variables
cluster_name="cluster1"## Get node names
CONFIG_FILE="${WAS_HOME}/profiles/$manage_profile1/logs/AboutThisProfile.txt"
NODE_NAME3=$(grep "Node name:" "$CONFIG_FILE" | awk '{print $NF}')

CONFIG_FILE="${WAS_HOME}/profiles/$manage_profile2/logs/AboutThisProfile.txt"
NODE_NAME4=$(grep "Node name:" "$CONFIG_FILE" | awk '{print $NF}')


# Create cluster
echo "AdminTask.createCluster('[-clusterConfig [-clusterName $cluster_name -preferLocal true]]')" > cls.py
echo "AdminTask.createClusterMember('[-clusterName $cluster_name -memberConfig [-memberNode $NODE_NAME3 -memberName $member_name -memberWeight 2 -genUniquePorts true -replicatorEntry false] -firstMember [-templateName default -nodeGroup DefaultNodeGroup -coreGroup DefaultCoreGroup -resourcesScope cluster]]')" >> cls.py
echo "AdminConfig.save()" >> cls.py

# Execute cluster creation script
${WAS_HOME}/bin/wsadmin.sh -lang jython -conntype SOAP -host $host -port $soap_port -user "$admin_Username" -password "$admin_Password" -f cls.py

# Create second cluster member
echo "AdminTask.createClusterMember('[-clusterName $cluster_name -memberConfig [-memberNode $NODE_NAME4 -memberName $member_name1 -memberWeight 2 -genUniquePorts true -replicatorEntry false]]')" >> cls1.py
echo "AdminConfig.save()" >> cls1.py

# Execute second cluster member creation script
${WAS_HOME}/bin/wsadmin.sh -lang jython -conntype SOAP -host $host -port $soap_port -user "$admin_username" -password "$admin_password" -f cls1.py

# Stop and start nodes and servers
$WAS_HOME/profiles/$manage_profile1/bin/stopNode.sh
$WAS_HOME/profiles/$manage_profile1/bin/syncNode.sh $host $soap_port
$WAS_HOME/profiles/$manage_profile1/bin/startNode.sh
$WAS_HOME/profiles/$manage_profile1/bin/startServer.sh "$member_name"

$WAS_HOME/profiles/$manage_profile2/bin/stopNode.sh
$WAS_HOME/profiles/$manage_profile2/bin/syncNode.sh $host $soap_port
$WAS_HOME/profiles/$manage_profile2/bin/startNode.sh
$WAS_HOME/profiles/$manage_profile2/bin/startServer.sh "$member_name1"
###########################################################################################################################

#######################application deployement###########################################################

applicationPath=/opt/SendJmsMessageEar.ear

CONFIG_FILE=/opt/IBM/WebSphere/AppServer/profiles/$dmgr_name/logs/AboutThisProfile.txt
member_name="member1"cellName=$(grep "Cell name:" "$CONFIG_FILE" | awk '{print $NF}')
clusterName=cluster1

echo "AdminApp.install('$applicationPath', '[ -nopreCompileJSPs -distributeApp -nouseMetaDataFromBinary -nodeployejb -appname SendJmsMessageEar -createMBeansForResources -noreloadEnabled -nodeployws -validateinstall warn -noprocessEmbeddedConfig -filepermission .*\.dll=755#.*\.so=755#.*\.a=755#.*\.sl=755 -noallowDispatchRemoteInclude -noallowServiceRemoteInclude -asyncRequestDispatchType DISABLED -nouseAutoLink -noenableClientModule -clientMode isolated -novalidateSchema -MapModulesToServers [[ SendJmsMessage SendJmsMessage.war,WEB-INF/web.xml WebSphere:cell=$cellName,cluster=$clusterName ]] -MapWebModToVH [[ SendJmsMessage SendJmsMessage.war,WEB-INF/web.xml default_host ]]]' )" > app.py
echo "AdminConfig.save()" >> app.py
/opt/IBM/WebSphere/AppServer/bin/wsadmin.sh -lang jython -conntype SOAP -host $host -port $soap_port -username $admin_username -password $admin_password -f app.py

#########################################################################################################

#####jms cofiguration################################################################

Name=Bus1
CONFIG_FILE=/opt/IBM/WebSphere/AppServer/profiles/$dmgr_name/logs/AboutThisProfile.txt
dmgrNodeName=$(grep "Node name:" "$CONFIG_FILE" | awk '{print $NF}')

CONFIG_FILE=/opt/IBM/WebSphere/AppServer/profiles/$dmgr_name/logs/AboutThisProfile.txt
cellName=$(grep "Cell name:" "$CONFIG_FILE" | awk '{print $NF}')

echo "AdminTask.createSIBus('[-bus $busName -busSecurity true -scriptCompatibility 6.1 ]')" > busCreation.py
echo "AdminTask.getSecurityDomainForResource('[-resourceName SIBus=$busName -getEffectiveDomain false]')" >> busCreation.py
echo "AdminTask.modifySIBus('[-bus $busName -busSecurity true -permittedChains SSL_ENABLED ]')" >> busCreation.py
echo "AdminConfig.save()" >> busCreation.py
echo "AdminConfig.reset()" >> busCreation.py
echo "AdminTask.listSIBuses()" >> busCreation.py
echo "AdminControl.invoke('WebSphere:name=DeploymentManager,process=dmgr,platform=common,node=$dmgrNodeName,diagnosticProvider=true,version=8.5.5.15,type=DeploymentManager,mbeanIdentifier=DeploymentManager,cell=$cellName,spec=1.0', 'multiSync', '[false]', '[java.lang.Boolean]')" >> busCreation.py

/opt/IBM/WebSphere/AppServer/bin/wsadmin.sh -lang jython -conntype SOAP -host $host -port $soap_port -username $admin_username -password $admin_password -f busCreation.py

clusterName=cluster1
logDirectoryPath=/opt/
permanentStoreDirectoryPath=/opt/
temporaryStoreDirectory=/opt/

CONFIG_FILE="/opt/IBM/WebSphere/AppServer/profiles/$manage_profile1/logs/AboutThisProfile.txt"
NODE_NAME1="$(grep 'Node name:' "$CONFIG_FILE" | awk '{print $NF}')"
echo "$NODE_NAME1"

CONFIG_FILE="/opt/IBM/WebSphere/AppServer/profiles/$manage_profile2/logs/AboutThisProfile.txt"
NODE_NAME2="$(grep 'Node name:' "$CONFIG_FILE" | awk '{print $NF}')"
member_name1="member2"
admin_Username="wasadmin"
admin_Password="sarasu10"
WAS_HOME="/opt/IBM/WebSphere/AppServer"
################################creation of servers#####################################################################
## Get node names
CONFIG_FILE="${WAS_HOME}/profiles/$manage_profile1/logs/AboutThisProfile.txt"
NODE_NAME1=$(grep "Node name:" "$CONFIG_FILE" | awk '{print $NF}')

CONFIG_FILE="${WAS_HOME}/profiles/$manage_profile2/logs/AboutThisProfile.txt"
NODE_NAME2=$(grep "Node name:" "$CONFIG_FILE" | awk '{print $NF}')
echo "$NODE_NAME2"

echo "AdminTask.addSIBusMember('[-bus $busName -cluster $clusterName -enableAssistance true -policyName HA -fileStore -logSize 100 -logDirectory $logDirectoryPath -minPermanentStoreSize 200 -maxPermanentStoreSize 500 -unlimitedPermanentStoreSize false -permanentStoreDirectory $permanentStoreDirectoryPath -minTemporaryStoreSize 200 -maxTemporaryStoreSize 500 -unlimitedTemporaryStoreSize false -temporaryStoreDirectory $temporaryStoreDirectory ]')" > busMembers.py
echo "AdminConfig.save()" >> busMembers.py
echo "AdminTask.listSIBusMembers('[-bus $busName ]')" >> busMembers.py
echo "AdminTask.stopMiddlewareServer('[-serverName $member_name -nodeName $NODE_NAME1 ]')" >> busMembers.py
echo "AdminTask.stopMiddlewareServer('[-serverName $member_name1 -nodeName $NODE_NAME2 ]')" >> busMembers.py
echo "AdminTask.startMiddlewareServer('[-serverName $member_name  -nodeName $NODE_NAME1 ]')" >> busMembers.py
echo "AdminTask.startMiddlewareServer('[-serverName $member_name1 -nodeName $NODE_NAME2 ]')" >> busMembers.py
/opt/IBM/WebSphere/AppServer/bin/wsadmin.sh -lang jython -conntype SOAP -host $host -port $soap_port -username $admin_username -password $admin_password -f busMembers.py

clusterName=cluster1
connectionFactoryName=connectionFactory
jndiName=Jms/cf
busName=Bus
echo "AdminTask.createSIBJMSConnectionFactory('$clusterName(cells/$cellName/clusters/$clusterName|cluster.xml)', '[-type queue -name $connectionFactoryName -jndiName $jndiName -description -category -busName $busName -nonPersistentMapping ExpressNonPersistent -readAhead Default -tempQueueNamePrefix -target -targetType BusMember -targetSignificance Preferred -targetTransportChain -providerEndPoints -connectionProximity Bus -authDataAlias -containerAuthAlias -mappingAlias -shareDataSourceWithCMP false -logMissingTransactionContext false -manageCachedHandles false -xaRecoveryAuthAlias -persistentMapping ReliablePersistent -consumerDoesNotModifyPayloadAfterGet false -producerDoesNotModifyPayloadAfterSet false]')" > jmsResource.py

queueJNDI=Jms/que
echo "AdminTask.createSIBJMSQueue('$clusterName(cells/$cellName/clusters/$clusterName|cluster.xml)', '[-name queue -jndiName $queueJNDI -description -deliveryMode Application -readAhead AsConnection -busName $busName -queueName _SYSTEM.Exception.Destination.cluster.000-$busName -scopeToLocalQP false -producerBind false -producerPreferLocal true -gatherMessages false]') " >> jmsResource.py
echo "AdminConfig.save()" >> jmsResource.py
echo "AdminConfig.reset()" >> jmsResource.py
echo "AdminControl.invoke('WebSphere:name=DeploymentManager,process=dmgr,platform=common,node=$dmgrNodeName,diagnosticProvider=true,version=8.5.5.15,type=DeploymentManager,mbeanIdentifier=DeploymentManager,cell=$cellName,spec=1.0', 'multiSync', '[false]', '[java.lang.Boolean]')" >> jmsResource.py
/opt/IBM/WebSphere/AppServer/bin/wsadmin.sh -lang jython -conntype SOAP -host $host -port $soap_port -username wasadmin -password sarasu10 -f jmsResource.pyopt/IBM/WebSphere/AppServer/bin/wsadmin.sh -lang jython -conntype SOAP -host $host -port $soap_port -username $admin_username -password $admin_password -f jmsResource.py

###############################################################################################################


#####jdbc configuration##########################################################################################
#J2C authentication
db2username=db2inst1
db2password=sarasu10
echo "AdminTask.createAuthDataEntry('[-alias DB2 -user $db2username -password $db2password -description "db2 configuration"]')" > j2Cauthentication.py
echo "AdminConfig.save()" >> j2Cauthentication.py
/opt/IBM/WebSphere/AppServer/bin/wsadmin.sh -lang jython -conntype SOAP -host $host -port $soap_port -username $admin_username -password $admin_password -f j2Cauthentication.py

#Creating JDBC provider

#Enter the classpath for db2jcc.jar and db2jcc_license_cu.jar file
db2jcc=/opt/db2jcc.jar
db2jcc_license_cu=/opt/db2jcc_license_cu.jar
#Enter the native path(Installation path) of db2
nativePath=/opt/ibm/db2/V10.5
echo "AdminTask.createJDBCProvider('[-scope Cluster=$cluster_name \
-databaseType DB2 \
-providerType \"DB2 Universal JDBC Driver Provider\" \
-implementationType \"Connection pool data source\" \
-name \"DB2 Universal JDBC Driver Provider\" \
-description \"One-phase commit DB2 JCC provider that supports JDBC 3.0. Data sources that use this provider support only 1-phase commit processing, unless you use driver type 2 with the application server for z/OS. If you use the application server for z/OS, driver type 2 uses RRS and supports 2-phase commit processing.\" \
-classpath [$db2jcc $db2jcc_license_cu] \
-nativePath [$nativePath] \
]')" > jdbcResource.py
echo "AdminConfig.save()" >> jdbcResource.py
/opt/IBM/WebSphere/AppServer/bin/wsadmin.sh -lang jython -conntype SOAP -host $host -port $soap_port -username $admin_username -password $admin_password -f jdbcResource.py

#Creating data source with existing JDBC Driver
echo "print(AdminConfig.list('JDBCProvider', AdminConfig.getid( '/Cell:$CELL_NAME/ServerCluster:$cluster_name/')))" > providerDetails.py
/opt/IBM/WebSphere/AppServer/bin/wsadmin.sh -lang jython -conntype SOAP -host $host -port $soap_port -username "wasadmin" -password "sarasu10" -f providerDetails.py | grep "DB2 Universal JDBC Driver Provider" > providerDetails.txt
jdbc_provider=$(<providerDetails.txt)


echo "AdminTask.createDatasource('$jdbc_provider', '[-name dataSource -jndiName db2 -dataStoreHelperClassName com.ibm.websphere.rsadapter.DB2UniversalDataStoreHelper -containerManagedPersistence true -componentManagedAuthenticationAlias $dmgrNODE_NAME/DB2 -configureResourceProperties [[databaseName java.lang.String eidiko] [driverType java.lang.Integer 4] [serverName java.lang.String 192.168.3.70] [portNumber java.lang.Integer 50000]]]')" > dataSource.py
echo "AdminConfig.save()" >> dataSource.py
/opt/IBM/WebSphere/AppServer/bin/wsadmin.sh -lang jython -conntype SOAP -host $host -port $soap_port -username $admin_username -password $admin_password -f dataSource.py
