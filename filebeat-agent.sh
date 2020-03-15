function filebeat_agent() {
     #import elasticsearch key
    rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
    
    #create elasticsearch repo
echo '[elasticsearch-7.x]
name=Elasticsearch repository for 7.x packages
baseurl=https://artifacts.elastic.co/packages/7.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md' > /etc/yum.repos.d/elasticsearch.repo

    yum -y install filebeat
    #disable elasticsearch for filebeat
    sed -i 's/output.elasticsearch:/#output.elasticsearch:/g'  /etc/filebeat/filebeat.yml
    sed -i '/localhost:9200/c\#  hosts: ["localhost:9200"]' /etc/filebeat/filebeat.yml

    #enable logstash for filebeat
    if [[ $1 == "" ]]
    then
    read -p "Enter your logstash Server_IP:port = " ip_port
    else
    ip_port="$1"
    fi
    sed -i '/output.logstash/c\output.logstash:' /etc/filebeat/filebeat.yml
    sed -i "/localhost:5044/c\  hosts: [\""$ip_port"\"]" /etc/filebeat/filebeat.yml
    
    #mv /etc/filebeat/modules.d/system.yml.disabled /etc/filebeat/modules.d/system.yml

    systemctl enable filebeat
    systemctl start filebeat

}

filebeat_agent
