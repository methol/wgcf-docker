#!/usr/bin/env bash

set -e

# Clean up and exit on error
_cleanup() {
  echo
  echo "Cleaning up..."
  if ! wg-quick down wgcf; then
    echo "Error stopping WireGuard interface."
  fi
  echo "Cleanup completed."
  exit 0
}

# Run WireGuard setup
_runwgcf() {
  trap '_cleanup' ERR TERM INT

  _enableV4="1"
  if [ "$1" = "-6" ]; then
    _enableV4=""
  fi

  # Register if necessary
  if [ ! -e "wgcf-account.toml" ]; then
    wgcf register --accept-tos
  fi

  # Generate WireGuard config if necessary
  if [ ! -e "wgcf-profile.conf" ]; then
    wgcf generate
  fi
  
  # Copy config to WireGuard directory
  cp wgcf-profile.conf /etc/wireguard/wgcf.conf

  # Get default gateway information
  DEFAULT_GATEWAY_NETWORK_CARD_NAME=$(route | grep default | awk '{print $8}' | head -1)
  DEFAULT_ROUTE_IP=$(ifconfig $DEFAULT_GATEWAY_NETWORK_CARD_NAME | grep "inet " | awk '{print $2}' | sed "s/addr://")
  
  echo "Default Gateway Network Card Name: ${DEFAULT_GATEWAY_NETWORK_CARD_NAME}"
  echo "Default Route IP: ${DEFAULT_ROUTE_IP}"
  
  # Add PostDown and PostUp rules to the config file
  sed -i "/\[Interface\]/a PostDown = ip rule delete from $DEFAULT_ROUTE_IP lookup main" /etc/wireguard/wgcf.conf
  sed -i "/\[Interface\]/a PostUp = ip rule add from $DEFAULT_ROUTE_IP lookup main" /etc/wireguard/wgcf.conf

  # Update AllowedIPs based on the address family
  if [ "$1" = "-6" ]; then
    sed -i 's/AllowedIPs = 0.0.0.0/#AllowedIPs = 0.0.0.0/' /etc/wireguard/wgcf.conf
  elif [ "$1" = "-4" ]; then
    sed -i 's/AllowedIPs = ::/#AllowedIPs = ::/' /etc/wireguard/wgcf.conf
  fi

  # Load ip6table_raw kernel module
  modprobe ip6table_raw

  # Start WireGuard interface
  wg-quick up wgcf
  
  # Sleep for WG start
  sleep 10
  
  # Check network based on address family
  if [ "$_enableV4" ]; then
    _checkV4
  else
    _checkV6
  fi

  echo
  echo "WireGuard setup completed. Enjoy secure browsing!"

  # Start a SOCKS5 proxy using gost
  gost -L socks5://:1080
}

# Check IPv4 connectivity
_checkV4() {
  echo "Checking network status (IPv4), please wait...."
  while ! curl --max-time 2 ipv4.ip.sb; do
    _cleanup
    echo "Sleeping for 2 seconds and retrying..."
    sleep 2
    wg-quick up wgcf
  done
}

# Check IPv6 connectivity
_checkV6() {
  echo "Checking network status (IPv6), please wait...."
  while ! curl --max-time 2 -6 ipv6.ip.sb; do
    _cleanup
    echo "Sleeping for 2 seconds and retrying..."
    sleep 2
    wg-quick up wgcf
  done
}

# Main entry point
if [ -z "$@" ] || [[ "$1" = -* ]]; then
  _runwgcf "$@"
else
  exec "$@"
fi
