## Install ELK on Centos7

``wget https://raw.githubusercontent.com/initedit-project/elk-install-bash/master/elk-install.sh``

``sed -i 's/\r//' elk-install.sh``

``bash elk-install.sh``

## Install filebeat agent to monitor servers

``wget https://raw.githubusercontent.com/initedit-project/elk-install-bash/master/filebeat-agent.sh``

``sed -i 's/\r//' filebeat-agent.sh``

``bash filebeat-agent.sh``

It will ask for logstash server IP and Port[eg. <b>192.168.0.1:5044</b> ]

<b>Note :</b> This script enables system module filebeat.
