#!/bin/bash
#   A script by Taurolyon
#   https://github.com/Taurolyon/failover

PRIMARY_IFACE=enp2s0
FAILOVER_IFACE=enp3s0
WAN_BOND_IFACE=wanbond0
PING_ADDRESS=8.8.8.8
FAILOVER_CHECK_INTERVAL=300 # check failover connection every 5 minutes
FAILOVER_FAILURE_THRESHOLD=3 # number of consecutive failures before logging a message
failedbounce=0

while true; do
    # Check primary interface for internet connectivity
    if ping -c 1 -I $PRIMARY_IFACE $PING_ADDRESS >/dev/null 2>&1; then
        # Internet connection is up on primary interface, set the default route to the WAN bond interface
        ip route replace default scope global dev $WAN_BOND_IFACE
        logger -t internet-monitor "Switched to $WAN_BOND_IFACE: Internet connection is up on $PRIMARY_IFACE"
        failedbounce=0
        sleep 60
        continue
    fi

    # Check failover interface for internet connectivity
    if ping -c 1 -I $FAILOVER_IFACE $PING_ADDRESS >/dev/null 2>&1; then
        # Internet connection is up on failover interface, set the default route to the failover interface
        ip route replace default scope global dev $FAILOVER_IFACE
        logger -t internet-monitor "Switched to $FAILOVER_IFACE: Internet connection is up on $FAILOVER_IFACE"
        failedbounce=0
        sleep 60
        continue
    fi

    # Both interfaces are down, set the default route to the failover interface
    ip route replace default scope global dev $FAILOVER_IFACE
    logger -t internet-monitor "Switched to $FAILOVER_IFACE: Both $PRIMARY_IFACE and $FAILOVER_IFACE are down"
    failedbounce=0
    sleep 60

    # Check failover interface for internet connectivity at regular intervals
    if [ $(( $SECONDS % $FAILOVER_CHECK_INTERVAL )) -eq 0 ]; then
        if ! ping -c 1 -I $FAILOVER_IFACE $PING_ADDRESS >/dev/null 2>&1; then
            # Failover interface is down, log a message if threshold is exceeded
            failedbounce=$(( $failedbounce + 1 ))
            if [ $failedbounce -eq $FAILOVER_FAILURE_THRESHOLD ]; then
                logger -t internet-monitor "Failover interface $FAILOVER_IFACE is down"
            fi
        else
            # Failover interface is up, log a message if it was previously down
            if [ $failedbounce -ge $FAILOVER_FAILURE_THRESHOLD ]; then
                logger -t internet-monitor "Failover interface $FAILOVER_IFACE is up"
            fi
            failedbounce=0
        fi
    fi
done
