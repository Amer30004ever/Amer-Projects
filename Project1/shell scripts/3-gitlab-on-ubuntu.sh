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

