#####Create 3 ubuntu machines

####Machine1:jenkins-GUI

###install jenkins:
  
sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" \
https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
/etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt-get update
sudo apt-get install fontconfig openjdk-17-jre
sudo apt-get install jenkins

####Machine2:

###install gitlab + prometheus + grafana

###1-install gitlab:

#!/bin/bash

#variables
HOST_IP=$(hostname -I | awk '{print $1}')

# Update package list and install necessary dependencies
sudo apt-get update
sudo apt-get install -y curl openssh-server ca-certificates tzdata perl

# Install Postfix for sending notification emails
sudo apt-get install -y postfix

# Postfix configuration: non-interactive setup
sudo debconf-set-selections <<< "postfix postfix/mailname string $(hostname)"
sudo debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"

# Add the GitLab package repository and install GitLab package
curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.deb.sh | sudo bash

# Install GitLab with the desired external URL
# Replace 'https://gitlab.example.com' with your own URL
sudo EXTERNAL_URL="$HOST_IP" apt-get install -y gitlab-ee

# Display message indicating completion
echo "GitLab installation is complete."
echo "You can access GitLab at: $HOST_IP"
echo "The initial root password can be found at /etc/gitlab/initial_root_password"
===========================================

###2-install prometheus + grafana:

#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to display a message and exit with a failure code
function fail {
  echo "$1" >&2
  exit 1
}

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
  fail "This script must be run as root."
fi

echo "Updating system package list..."
sudo apt-get update

echo "Creating Prometheus user and directories..."
sudo useradd --no-create-home --shell /bin/false prometheus
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /var/lib/prometheus

echo "Downloading Prometheus..."
PROMETHEUS_VERSION="2.46.0"
cd /tmp/
wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz

echo "Extracting Prometheus..."
tar -xvf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz

echo "Moving Prometheus files..."
cd prometheus-${PROMETHEUS_VERSION}.linux-amd64
sudo mv consoles /etc/prometheus
sudo mv console_libraries /etc/prometheus
sudo mv prometheus.yml /etc/prometheus/prometheus.yml
sudo chown -R prometheus:prometheus /etc/prometheus

sudo mv prometheus /usr/local/bin/
sudo chown prometheus:prometheus /usr/local/bin/prometheus

echo "Creating Prometheus systemd service file..."
cat <<EOF | sudo tee /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=:9091

[Install]
WantedBy=multi-user.target
EOF

# Modify the Prometheus systemd service file to match the new port
echo "Updating Prometheus systemd service file..."
sudo sed -i 's/--web.console.libraries=\/etc\/prometheus\/console_libraries/--web.console.libraries=\/etc\/prometheus\/console_libraries --web.listen-address=:9091/' /etc/systemd/system/prometheus.service

echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "Starting Prometheus service..."
sudo systemctl start prometheus
sudo systemctl enable prometheus

echo "Adding Grafana repository..."
sudo apt-get install -y apt-transport-https
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

echo "Updating package list and installing Grafana..."
sudo apt-get update
sudo apt-get install -y grafana

echo "Starting Grafana service..."
sudo systemctl enable --now grafana-server

echo "Setting up Grafana admin password..."
GRAFANA_PASSWORD="admin"
sudo systemctl stop grafana-server
sudo grafana-cli admin reset-admin-password $GRAFANA_PASSWORD
sudo systemctl start grafana-server

echo "Waiting for Grafana to start..."
sleep 10

echo "Configuring Prometheus as a data source in Grafana..."
GRAFANA_API_KEY=$(curl -s -X POST -H "Content-Type: application/json" -d '{"name":"API Key","role":"Admin"}' http://admin:${GRAFANA_PASSWORD}@localhost:3000/api/auth/keys | jq -r .key)
PROMETHEUS_URL="http://localhost:9090"
curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $GRAFANA_API_KEY" -d "{\"name\":\"Prometheus\",\"type\":\"prometheus\",\"url\":\"${PROMETHEUS_URL}\",\"access\":\"proxy\"}" http://localhost:3000/api/datasources

echo "Installation and configuration completed successfully!"
echo "Prometheus is running at http://localhost:9090"
echo "Grafana is running at http://localhost:3000 with username 'admin' and password '${GRAFANA_PASSWORD}'"
===========================================

##configure prometheus:
edit /etc/prometheus/prometheus.yml


global:
  scrape_interval:     15s
  evaluation_interval: 15s
  scrape_timeout:      10s

# Alertmanager configuration
alerting:
  alertmanagers:
  - static_configs:
    - targets:
      # - alertmanager:9093

# Load rules once and periodically evaluate them according to the global 'evaluation_interval'.
rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

# A scrape configuration containing exactly one endpoint to scrape:
# Here it's Prometheus itself.
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
    - targets: ['192.168.222.158:9091']
  - job_name: 'jenkins'
    metrics_path: /prometheus/
    static_configs:
    - targets: ['192.168.222.166:8080']



$ sudo systemctl daemon-reload
amer@strong-man:/etc/prometheus$ sudo systemctl restart prometheus.service
amer@strong-man:/etc/prometheus$ sudo systemctl status prometheus.service


in http://192.168.222.158:9091/
change metrics
jenkins_executor_count_value   and execute


##change grafana password
sudo systemctl stop grafana-server
sudo grafana-cli admin reset-admin-password 1234
sudo systemctl start grafana-server

##configure grafana
add new data source
connection >> data source
data source of prometheus:http://192.168.222.158:9091/

Dashboards >> new >> import >> 9964 load >> select Prometheus Data Source
Dashboard : Jenkins: Performance and Health Overview
choose prometheus Data source

####Machine3:jenkins-agent:

###install docker:

#!/bin/bash

# Update package index and install prerequisites
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

# Create directory for Docker's GPG key and add the key
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository to APT sources
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index again and install Docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify Docker installation
sudo docker run hello-world

# Optional: Add the current user to the Docker group
echo "Adding current user to the Docker group. Log out and back in to apply the group membership."
sudo groupadd docker

#added
newgrp docker

sudo usermod -aG docker $USER

echo "Docker installation is complete. Run 'docker run hello-world' after logging back in to verify the installation."
=====================================

###install Ansible:

sudo apt update
sudo apt install ansible

#creating SSH-key:
Create private and public SSH keys. The following command creates the private key jenkinsAgent_rsa and the public key jenkinsAgent_rsa.pub. 
It is recommended to store your keys under ~/.ssh/ so we move to that directory before creating the key pair.

 mkdir ~/.ssh; cd ~/.ssh/ && ssh-keygen -t rsa -m PEM -C "Jenkins agent key" -f "jenkinsAgent_rsa"

Add the public SSH key to the list of authorized keys on the agent machine
cat jenkinsAgent_rsa.pub >> ~/.ssh/authorized_keys

Ensure that the permissions of the ~/.ssh directory is secure, as most ssh daemons will refuse to use keys that have file permissions that are considered insecure:
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys ~/.ssh/jenkinsAgent_rsa

Copy the private SSH key (~/.ssh/jenkinsAgent_rsa) from the agent machine to your OS clipboard
cat ~/.ssh/jenkinsAgent_rsa

---------
jenkins devops plugins:

Ant Plugin
Build Timeout
CloudBees Disk Usage Simple Plugin
Docker Pipeline
Docker plugin
docker-build-step
ECharts API
Font Awesome API
Git
Git server Plugin
GitHub Branch Source
GitHub Integration Plugin
Gradle
JavaMail API
Kubernetes Credentials
Kubernetes plugin
LDAP Plugin
Matrix Authorization Strategy Plugin
Monitoring
PAM Authentication plugin
Pipeline
Pipeline Graph View
Pipeline: GitHub Groovy Libraries
Pipeline: Stage View Plugin
Prometheus metrics
Timestamper
Workspace Cleanup Plugin

create jenkins node on jenkins-GUI
new node > node name : jenins-agent , permanent agent > create > Number of executors : 2 >
remote root directory: /home/jenkins > labels: jenins-agent > usage : use this node as much as possible >
Launch methos: Launch agent via SSH > Credentials, Add-- kind: SSH Username with private key, ID: jenkins-agent,
Description: jenins-agent, username: jenkins, Private Key--enter directly: (paste ssh key of jenkins agent machine)
--Add --select Credentials:jenkins-agent > save --- login ssh to jenkins-agent machine from jenkins-GUI machine

create jenkins job
Dashboard > New Item > Source Code Management -- Git -- Repositories -- Repository URL: > Credentials : (add gitlab credentials)
Branches to build > Branch Specifier : (*/main)
Build Steps >  Add build step > Execute shell: cd Simple-Project/
								ansible-playbook ansible-playbook.yml


