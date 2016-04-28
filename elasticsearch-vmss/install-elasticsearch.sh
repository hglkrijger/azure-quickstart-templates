#!/bin/bash

# The MIT License (MIT)
#
# Copyright (c) 2015 Microsoft Azure
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

help()
{
    echo "This script installs Elasticsearch on Ubuntu"
    echo "Parameters:"
    echo "  -n elasticsearch cluster name"
    echo "  -a storage account (for blob discovery)"
    echo "  -k storage key (for blob discovery)"
    echo "  -h view this help content"
}

# Log method to control/redirect log output
log()
{
    echo "$1"
}

log "Begin execution of Elasticsearch script extension on ${HOSTNAME}"

if [ "${UID}" -ne 0 ];
then
    log "Script executed without root permissions"
    echo "You must be root to run this program." >&2
    exit 3
fi

# TEMP FIX - Re-evaluate and remove when possible
# This is an interim fix for hostname resolution in current VM
grep -q "${HOSTNAME}" /etc/hosts
if [ $? == 0 ]
then
  echo "${HOSTNAME} found in /etc/hosts"
else
  echo "${HOSTNAME} not found in /etc/hosts"
  # Append it to the hosts file if not there
  echo "127.0.0.1 ${HOSTNAME}" >> /etc/hosts
  log "hostname ${HOSTNAME} added to /etc/hosts"
fi

#Script Parameters
CLUSTER_NAME="elasticsearch"
ES_VERSION="2.3.1"
AZURE_ACCOUNT=""
AZURE_KEY=""

#Loop through options passed
while getopts :n:a:k:h optname; do
  log "Option $optname set with value ${OPTARG}"
  case $optname in
    n) #set cluster name
      CLUSTER_NAME=${OPTARG}
      ;;
    a) #set azure account
      AZURE_ACCOUNT=${OPTARG}
      ;;
    k) #set azure account key
      AZURE_KEY=${OPTARG}
      ;;
    h) #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
      help
      exit 2
      ;;
  esac
done

# Install Oracle Java
install_java()
{
	log "Installing Java"
	add-apt-repository -y ppa:webupd8team/java 
	apt-get -y update
    echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections
    echo debconf shared/accepted-oracle-license-v1-1 seen true | debconf-set-selections
	apt-get -y install oracle-java8-installer  > /dev/null
}

install_es()
{
    DOWNLOAD_URL="https://download.elasticsearch.org/elasticsearch/release/org/elasticsearch/distribution/deb/elasticsearch/$ES_VERSION/elasticsearch-$ES_VERSION.deb"
    log "Installing Elaticsearch $ES_VERSION from $DOWNLOAD_URL"
    wget -q "$DOWNLOAD_URL" -O elasticsearch.deb
	dpkg -i elasticsearch.deb
	log "Installing Blob-Discovery Plugin"
	/usr/share/elasticsearch/bin/plugin --url file:///./azuresearch-blob-discovery-plugin.zip --install blob-discovery-plugin
}

configure_es()
{
	log "Update configuration"
	mv /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.bak
	echo "cluster.name: $CLUSTER_NAME" >> /etc/elasticsearch/elasticsearch.yml
	echo "node.name: ${HOSTNAME}" >> /etc/elasticsearch/elasticsearch.yml
	echo "discovery.zen.ping.multicast.enabled: false" >> /etc/elasticsearch/elasticsearch.yml
	echo "discovery.type: microsoft.windowsazure.search.elasticsearch.plugins.BlobDiscoveryModule" >> /etc/elasticsearch/elasticsearch.yml
	echo "discovery.windowsazure.search.master_election.type: azure" >> /etc/elasticsearch/elasticsearch.yml
	echo "discovery.windowsazure.search.master_election.azure_storage_connection_string: DefaultEndpointsProtocol=https;AccountName=${AZURE_ACCOUNT};AccountKey=${AZURE_KEY}" >> /etc/elasticsearch/elasticsearch.yml
	echo "network.host: _non_loopback_" >> /etc/elasticsearch/elasticsearch.yml
}

configure_system()
{
	# DNS Retry
	echo "options timeout:1 attempts:5" >> /etc/resolvconf/resolv.conf.d/head
	resolvconf -u

	# Increase maximum mmap count
	echo "vm.max_map_count = 262144" >> /etc/sysctl.conf

	# Heap size
	ES_HEAP=`free -m |grep Mem | awk '{if ($2/2 >31744)  print 31744;else print $2/2;}'`
	echo "ES_HEAP_SIZE=${ES_HEAP}m" >> /etc/default/elasticsearch
}

start_service()
{
	log "Starting Elasticsearch on ${HOSTNAME}"
	update-rc.d elasticsearch defaults 95 10
	sudo service elasticsearch start
}

log "starting elasticsearch setup"

# wait for linux diagnostics extension to install
sleep 300

install_java
install_es
configure_es
configure_system
start_service

log "completed elasticsearch setup"
exit 0
