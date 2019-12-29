function dependency_conf() {
    #install java
    yum -y install java curl httpd-tools

    #open firewall for ELK
    #firewall-cmd --zone=public --add-port=9200/tcp --permanent
    firewall-cmd --zone=public --add-port=5044/tcp --permanent
    #firewall-cmd --zone=public --add-port=5601/tcp --permanent
    firewall-cmd --zone=public --add-port=80/tcp --permanent
    firewall-cmd --reload

    #disable selinux
    setenforce 0
    sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config

}

function elasticsearch_conf() {
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

    #install elasticsearch
    yum -y install elasticsearch

    #run elasticsearch on localhost:9200
    sed -i '/network.host/c\network.host: localhost' /etc/elasticsearch/elasticsearch.yml

    systemctl enable elasticsearch
    systemctl start elasticsearch

}

function kibana_conf() {
    yum -y install kibana
    systemctl enable kibana
    systemctl start kibana
}

function nginx_conf() {

    yum -y install epel-release
    yum -y install nginx
    server_ip=$(ip a | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -v 127.0.0.1 | awk '{ print $2 }' | cut -d "/" -f 1)
    export server_ip="$server_ip"

    #sed -i '0,+location+ s+        location / {+        location / {\nproxy_pass http://localhost:5601;+g' /etc/nginx/nginx.conf
    #sed 's+location / {+location / {\nproxy_pass http://localhost:5601;+g' /etc/nginx/nginx.conf
    if [[ $(cat /etc/nginx/nginx.conf |  grep 'proxy_pass' ) == "" ]]
    then
    sed -i '48i proxy_pass http://localhost:5601;' /etc/nginx/nginx.conf
    fi

    systemctl start nginx
    systemctl enable  nginx
}

function logstash_conf() {
    yum -y install logstash
    systemctl enable logstash

echo 'input {
  beats {
    port => 5044
  }
}' > /etc/logstash/conf.d/02-beats-input.conf

echo '
filter {
  if [fileset][module] == "system" {
    if [fileset][name] == "auth" {
      grok {
        match => { "message" => ["%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} sshd(?:\[%{POSINT:[system][auth][pid]}\])?: %{DATA:[system][auth][ssh][event]} %{DATA:[system][auth][ssh][method]} for (invalid user )?%{DATA:[system][auth][user]} from %{IPORHOST:[system][auth][ssh][ip]} port %{NUMBER:[system][auth][ssh][port]} ssh2(: %{GREEDYDATA:[system][auth][ssh][signature]})?",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} sshd(?:\[%{POSINT:[system][auth][pid]}\])?: %{DATA:[system][auth][ssh][event]} user %{DATA:[system][auth][user]} from %{IPORHOST:[system][auth][ssh][ip]}",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} sshd(?:\[%{POSINT:[system][auth][pid]}\])?: Did not receive identification string from %{IPORHOST:[system][auth][ssh][dropped_ip]}",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} sudo(?:\[%{POSINT:[system][auth][pid]}\])?: \s*%{DATA:[system][auth][user]} :( %{DATA:[system][auth][sudo][error]} ;)? TTY=%{DATA:[system][auth][sudo][tty]} ; PWD=%{DATA:[system][auth][sudo][pwd]} ; USER=%{DATA:[system][auth][sudo][user]} ; COMMAND=%{GREEDYDATA:[system][auth][sudo][command]}",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} groupadd(?:\[%{POSINT:[system][auth][pid]}\])?: new group: name=%{DATA:system.auth.groupadd.name}, GID=%{NUMBER:system.auth.groupadd.gid}",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} useradd(?:\[%{POSINT:[system][auth][pid]}\])?: new user: name=%{DATA:[system][auth][user][add][name]}, UID=%{NUMBER:[system][auth][user][add][uid]}, GID=%{NUMBER:[system][auth][user][add][gid]}, home=%{DATA:[system][auth][user][add][home]}, shell=%{DATA:[system][auth][user][add][shell]}$",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} %{DATA:[system][auth][program]}(?:\[%{POSINT:[system][auth][pid]}\])?: %{GREEDYMULTILINE:[system][auth][message]}"] }
        pattern_definitions => {
          "GREEDYMULTILINE"=> "(.|\n)*"
        }
        remove_field => "message"
      }
      date {
        match => [ "[system][auth][timestamp]", "MMM  d HH:mm:ss", "MMM dd HH:mm:ss" ]
      }
      geoip {
        source => "[system][auth][ssh][ip]"
        target => "[system][auth][ssh][geoip]"
      }
    }
    else if [fileset][name] == "syslog" {
      grok {
        match => { "message" => ["%{SYSLOGTIMESTAMP:[system][syslog][timestamp]} %{SYSLOGHOST:[system][syslog][hostname]} %{DATA:[system][syslog][program]}(?:\[%{POSINT:[system][syslog][pid]}\])?: %{GREEDYMULTILINE:[system][syslog][message]}"] }
        pattern_definitions => { "GREEDYMULTILINE" => "(.|\n)*" }
        remove_field => "message"
      }
      date {
        match => [ "[system][syslog][timestamp]", "MMM  d HH:mm:ss", "MMM dd HH:mm:ss" ]
      }
    }
  }
}' > /etc/logstash/conf.d/10-syslog-filter.conf

echo '
output {
  elasticsearch {
    hosts => ["localhost:9200"]
    manage_template => false
    index => "%{[@metadata][beat]}-%{[@metadata][version]}-%{+YYYY.MM.dd}"
  }
}' > /etc/logstash/conf.d/30-elasticsearch-output.conf

systemctl enable logstash
systemctl start logstash

}

function filebeat_conf() {

    yum -y install filebeat
    #disable elasticsearch for filebeat
    sed -i 's/output.elasticsearch:/#output.elasticsearch:/g'  /etc/filebeat/filebeat.yml
    sed -i '/localhost:9200/c\#  hosts: ["localhost:9200"]' /etc/filebeat/filebeat.yml

    #enable logstash for filebeat
    sed -i '/output.logstash/c\output.logstash:' /etc/filebeat/filebeat.yml
    sed -i '/localhost:5044/c\  hosts: ["localhost:5044"]' /etc/filebeat/filebeat.yml
    
    mv /etc/filebeat/modules.d/system.yml.disabled /etc/filebeat/modules.d/system.yml

    systemctl enable filebeat
    systemctl start filebeat

}

function heartbeat_conf() {

  yum -y install heartbeat-elastic
  systemctl start heartbeat-elastic
  systemctl enable heartbeat-elastic

}

function nginx_passwd_protect() {

  echo "Restrict Nginx access with username and password:"
  read -p "Username : " uname
  htpasswd -c /etc/nginx/elk-passwd.$uname $uname
  
  if [[ -f /etc/nginx/elk-passwd.$uname ]]
  then

  if [[ $(cat /etc/nginx/nginx.conf | grep 'auth_basic_user_file') == "" ]]
  then
  sed -i "45i auth_basic_user_file /etc/nginx/elk-passwd.$uname;" /etc/nginx/nginx.conf
  sed -i '45i auth_basic "Restricted Access";' /etc/nginx/nginx.conf
  fi

  fi
  systemctl restart nginx
}

# call
dependency_conf

elasticsearch_conf

kibana_conf

nginx_conf

logstash_conf

filebeat_conf

heartbeat_conf

nginx_passwd_protect

echo " ======================== Completed ========================"
echo "Elasticsearch: http://localhost:9200"
echo "Logstash: http://0.0.0.0:5044 or $(curl -s ifconfig.me):5044 or $server_ip:5044"
echo "kibana: http://localhost:5601"
echo "Nginx(proxy for kibana): http://$server_ip or http://$(curl -s ifconfig.me)"
echo "Nginx login username: $uname"
echo " ==========================================================="