#!/bin/sh

# set up the timezone
timedatectl set-timezone "America/Los_Angeles"

# ensure there's a baseline debian source for testing

grep -i "httpredir.debian.org/debian testing" /etc/apt/sources.list || echo "deb http://httpredir.debian.org/debian testing main contrib non-free" >> /etc/apt/sources.list

# make sure the clock is OK:
systemctl enable systemd-timesyncd
systemctl restart systemd-timesyncd

timedatectl set-local-rtc 0
timedatectl set-ntp 1
systemctl restart systemd-timesyncd

sleep 5

#now that the time is correct, we won't have signature issues with package sources

apt-get update
apt-get -y install yggdrasil

grep "corn.chowder.land" /etc/yggdrasil/yggdrasil.conf || yggdrasil -genconf | 
  sed -E -e "s&Peers:.*&Peers: [\ntcp://corn.chowder.land:9002\n]&" -e "s/IfName.*/IfName: ygg0/" > /etc/yggdrasil/yggdrasil.conf


cat > /etc/nftables.conf << EOF

table inet filter {

      chain input {
		type filter hook input priority 0; policy drop;

		# established/related connections
		ct state established,related accept

    #ipv6 multicast
		ip6 saddr fe80::/16 pkttype multicast accept

		tcp dport {5500,5900} accept # incoming remote desktop 
    udp dport {5353, 9001} pkttype multicast accept
    
		# ICMP & IGMP
		ip6 nexthdr icmpv6 limit rate 10/second burst 20 packets accept
		ip protocol icmp limit rate 10/second burst 20 packets accept
		ip protocol igmp limit rate 10/second burst 20 packets accept

		# SSH (port 22)
		ct state new ip protocol tcp tcp dport ssh  meter ssh-meter4 {ip saddr limit rate 10/minute burst 10 packets} accept
		ct state new ip6 nexthdr tcp tcp dport ssh  meter ssh-meter6 {ip6 saddr limit rate 10/minute burst 10 packets} accept

    counter log prefix "DROP INPUT: " drop
	}

	chain forward {
	    type filter hook forward priority 0; policy drop;
	    iifname lo accept
	    iifname ygg0 drop #yggdrasil
	    counter log prefix "DROP FORWARD: " drop
	}

	chain output {
		type filter hook output priority 0; policy accept;
	}
}

EOF

systemctl enable yggdrasil
systemctl restart yggdrasil
systemctl restart nftables

ip addr show
