#!/bin/bash
#
# Simple firewall - A good starting point
#

### Configuration
## Source config file
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ -e "${DIR}/config" ]; then
  . ${DIR}/config
fi

# Defaults
NAGIOS_SERVER=${NAGIOS_SERVER-'monitor.example.com'}
FW_SSH_PORT=${FW_SSH_PORT-'22'}
###

# Delete all existing rules and chains
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# Input Rules
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p icmp -m icmp --icmp-type any -j ACCEPT
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp -m state --state NEW -m tcp --source ${NAGIOS_SERVER} --dport 5666 -j ACCEPT # NRPE
iptables -A INPUT -p tcp -m state --state NEW -m tcp --dport ${FW_SSH_PORT} -j ACCEPT
iptables -A INPUT -j DROP

# Output Rules
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -p icmp -m icmp --icmp-type any -j ACCEPT
iptables -A OUTPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -p tcp -m state --state NEW -m tcp --dport ${FW_SSH_PORT} -j ACCEPT
iptables -A OUTPUT -p tcp -m state --state NEW -m tcp --dport 25 -j ACCEPT
iptables -A OUTPUT -p tcp -m state --state NEW -m tcp --dport 53 -j ACCEPT
iptables -A OUTPUT -p udp -m state --state NEW -m udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p udp -m state --state NEW -m udp -m owner --uid-owner root --dport 123 -j ACCEPT
iptables -A OUTPUT -p tcp -m state --state NEW -m tcp -m owner --uid-owner root --dport 80 -j ACCEPT
iptables -A OUTPUT -p tcp -m state --state NEW -m tcp -m owner --uid-owner root --dport 443 -j ACCEPT
iptables -A OUTPUT -p tcp -m state --state NEW -m tcp --destination ${NAGIOS_SERVER} --dport 5667 -j ACCEPT # NSCA
iptables -A OUTPUT -j REJECT --reject-with icmp-host-prohibited

# Forward Rules
iptables -A FORWARD -j DROP
