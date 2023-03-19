#!/bin/bash
#   A script by Taurolyon
#   https://github.com/Taurolyon/failover

PRIMARY_IFACE=enp2s0
FAILOVER_IFACE=enp3s0
PING_ADDRESS=8.8.8.8
FAILOVER_CHECK_INTERVAL=300 # check failover connection every 5 minutes
FAILOVER_FAILURE_THRESHOLD=3 # number of consecutive failures before logging a message
failedbounce=0

#debugging outputs
# Get the default gateway for the primary interface
if ifplugstatus $PRIMARY_IFACE >/dev/null; then
    PRIMARY_GATEWAY=$(ip route get $PING_ADDRESS | awk 'NR==1{print $(NF-2)}')
    echo "Primary interface: $PRIMARY_IFACE"
    echo "Primary gateway: $PRIMARY_GATEWAY"
else
    echo "Primary interface $PRIMARY_IFACE is not connected!"
fi

# Get the default gateway for the failover interface
if ifplugstatus $FAILOVER_IFACE >/dev/null; then
    FAILOVER_GATEWAY=$(ip route get $PING_ADDRESS | awk 'NR==2{print $(NF-2)}')
    echo "Failover interface: $FAILOVER_IFACE"
    echo "Failover gateway: $FAILOVER_GATEWAY"
else
    echo "Failover interface $FAILOVER_IFACE is not connected!"
fi

while true; do
     # Check link status of primary interface
    if ifplugstatus $PRIMARY_IFACE | grep -q "link beat detected"; then
        echo "Link is up on $PRIMARY_IFACE"
    else
        echo "Link is down on $PRIMARY_IFACE"
        sleep 10
        continue
    fi

    # Check link status of failover interface
    if ifplugstatus $FAILOVER_IFACE | grep -q "link beat detected"; then
        echo "Link is up on $FAILOVER_IFACE"
    else
        echo "Link is down on $FAILOVER_IFACE"
        sleep 10
        continue
    fi

    # Check primary interface for internet connectivity
    echo "Checking internet connectivity on primary interface: $PRIMARY_IFACE"
    if ifplugstatus $PRIMARY_IFACE >/dev/null && ping -c 1 -I $PRIMARY_IFACE $PING_ADDRESS >/dev/null 2>&1; then
        # Internet connection is up on primary interface, set the default route to the primary interface
        ip route replace default via $PRIMARY_GATEWAY dev $PRIMARY_IFACE
        logger -t internet-monitor "Switched to Primary: Internet connection is up on $PRIMARY_IFACE"
        echo "Switched to Primary: Internet connection is up on $PRIMARY_IFACE"
        failedbounce=0
        sleep 60
        continue
    fi

    # Check failover interface for internet connectivity
    if ifplugstatus $FAILOVER_IFACE >/dev/null && ping -c 1 -I $FAILOVER_IFACE $PING_ADDRESS >/dev/null 2>&1; then
        # Internet connection is up on failover interface, set the default route to the failover interface
        ip route replace default via $FAILOVER_GATEWAY dev $FAILOVER_IFACE
        logger -t internet-monitor "Switched to Failover: Internet connection is up on $FAILOVER_IFACE"
        echo "Switched to Failover: Internet connection is up on $FAILOVER_IFACE"
        failedbounce=0
        sleep 60
        continue
    fi

    # Both interfaces are down
    logger -t internet-monitor "ERROR: Both $PRIMARY_IFACE and $FAILOVER_IFACE are down!!"
    echo "ERROR: Both $PRIMARY_IFACE and $FAILOVER_IFACE are down!!"
    failedbounce=0
    sleep 30

    # Check failover interface for internet connectivity at regular intervals
    if [ $(( $SECONDS % $FAILOVER_CHECK_INTERVAL )) -eq 0 ]; then
        if ! ping -c 1 -I $FAILOVER_IFACE $PING_ADDRESS >/dev/null 2>&1; then
            # Failover interface is down, log a message if threshold is exceeded
            failedbounce=$(( $failedbounce + 1 ))
            if [ $failedbounce -eq $FAILOVER_FAILURE_THRESHOLD ]; then
                logger -t internet-monitor "Failover interface $FAILOVER_IFACE is down"
                echo "Failover interface $FAILOVER_IFACE is down"
            fi
        else
            # Failover interface is up, log a message if it was previously down
            if [ $failedbounce -ge $FAILOVER_FAILURE_THRESHOLD ]; then
                logger -t internet-monitor "Failover interface $FAILOVER_IFACE is up"
                echo "Failover interface $FAILOVER_IFACE is up"
            fi
            failedbounce=0
        fi
    fi
done
