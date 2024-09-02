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

