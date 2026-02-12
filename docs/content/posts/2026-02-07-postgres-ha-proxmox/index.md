---
title: "Deploying PostgreSQL with High Availability on Proxmox"
date: 2026-02-07
draft: true
description: "A comprehensive guide to deploying a highly available PostgreSQL database cluster on Proxmox VE"
summary: "Learn how to set up a production-ready PostgreSQL cluster with streaming replication, automatic failover, and load balancing on Proxmox virtualization platform"
tags: ["postgresql", "proxmox", "high-availability", "database", "homelab", "replication"]
---

# Deploying PostgreSQL with High Availability on Proxmox

High availability (HA) is crucial for production database systems. In this guide, we'll walk through deploying a PostgreSQL database cluster with automatic failover capabilities on Proxmox VE, a powerful open-source virtualization platform.

## Introduction

PostgreSQL is one of the most advanced open-source relational database systems, and when combined with Proxmox's virtualization capabilities, you can create a robust, highly available database infrastructure suitable for production workloads.

### What We'll Build

By the end of this guide, you'll have:

- Three PostgreSQL nodes (1 primary + 2 replicas)
- Automatic failover using Patroni
- Distributed configuration store with etcd
- Connection pooling and load balancing with HAProxy
- Monitoring and health checks

### Why This Architecture?

This setup provides:

- **Zero downtime**: Automatic failover when the primary fails
- **Read scalability**: Distribute read queries across replicas
- **Data durability**: Multiple copies of your data
- **Easy maintenance**: Rolling updates without downtime

## Prerequisites

Before starting, ensure you have:

- Proxmox VE 7.x or 8.x installed and configured
- At least 3 available IP addresses on your network
- Basic understanding of Linux system administration
- Minimum 8GB RAM available across your Proxmox cluster
- At least 50GB of storage for each VM

### Network Planning

Plan your network configuration:

- **Primary Node**: 192.168.1.101
- **Replica Node 1**: 192.168.1.102
- **Replica Node 2**: 192.168.1.103
- **HAProxy VIP**: 192.168.1.100 (virtual IP for clients)

*Note: Adjust these IPs to match your network configuration.*

## Part 1: Setting Up Proxmox Virtual Machines

### Creating the VMs

We'll create three identical VMs for our PostgreSQL cluster.

1. **Log into Proxmox Web Interface** at `https://your-proxmox-ip:8006`

2. **Create the first VM:**
   - Click "Create VM" in the top right
   - **General**: VM ID: 101, Name: `pg-primary`
   - **OS**: Select your preferred Linux ISO (Ubuntu 22.04 LTS or Debian 12 recommended)
   - **System**: Default settings, enable Qemu Agent
   - **Disks**: 50GB, VirtIO SCSI
   - **CPU**: 2 cores (adjust based on workload)
   - **Memory**: 4096MB (4GB)
   - **Network**: VirtIO, Bridge to vmbr0

3. **Install the Operating System** on the first VM

4. **Clone the VM** to create two more nodes:

   ```bash
   # From Proxmox shell or via Web UI
   qm clone 101 102 --name pg-replica1 --full
   qm clone 101 103 --name pg-replica2 --full
   ```

### Initial VM Configuration

SSH into each VM and perform the following steps:

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install essential tools
sudo apt install -y curl wget gnupg2 software-properties-common apt-transport-https lsb-release ca-certificates

# Set hostname (adjust for each node)
sudo hostnamectl set-hostname pg-primary  # or pg-replica1, pg-replica2

# Configure static IP addresses
# Edit /etc/netplan/00-installer-config.yaml (Ubuntu)
# or /etc/network/interfaces (Debian)
```

Example Netplan configuration for Ubuntu:

```yaml
network:
  version: 2
  ethernets:
    ens18:
      addresses:
        - 192.168.1.101/24  # Change for each node
      gateway4: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
```

Apply the network configuration:

```bash
sudo netplan apply  # Ubuntu
# or
sudo systemctl restart networking  # Debian
```

### Update /etc/hosts

Add entries on all three nodes:

```bash
sudo tee -a /etc/hosts <<EOF
192.168.1.101 pg-primary
192.168.1.102 pg-replica1
192.168.1.103 pg-replica2
EOF
```

## Part 2: Installing PostgreSQL

We'll install PostgreSQL 15 (or latest stable version) on all three nodes.

### Add PostgreSQL Repository

```bash
# Import PostgreSQL GPG key
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg

# Add repository
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list

# Update package list
sudo apt update
```

### Install PostgreSQL

```bash
# Install PostgreSQL 15 and contrib package
sudo apt install -y postgresql-15 postgresql-contrib-15

# Stop PostgreSQL (we'll configure it through Patroni)
sudo systemctl stop postgresql
sudo systemctl disable postgresql
```

## Part 3: Setting Up etcd for Distributed Configuration

etcd is a distributed key-value store that Patroni uses to maintain cluster state and coordinate failovers.

### Install etcd on All Nodes

```bash
# Install etcd
sudo apt install -y etcd

# Stop the default etcd service
sudo systemctl stop etcd
sudo systemctl disable etcd
```

### Configure etcd

Create etcd configuration on **each node** (adjust IP addresses accordingly):

```bash
sudo tee /etc/default/etcd <<EOF
ETCD_NAME=$(hostname)
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_LISTEN_PEER_URLS="http://$(hostname -I | awk '{print $1}'):2380"
ETCD_LISTEN_CLIENT_URLS="http://$(hostname -I | awk '{print $1}'):2379,http://127.0.0.1:2379"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://$(hostname -I | awk '{print $1}'):2380"
ETCD_ADVERTISE_CLIENT_URLS="http://$(hostname -I | awk '{print $1}'):2379"
ETCD_INITIAL_CLUSTER="pg-primary=http://192.168.1.101:2380,pg-replica1=http://192.168.1.102:2380,pg-replica2=http://192.168.1.103:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="postgres-cluster"
EOF

# Create data directory
sudo mkdir -p /var/lib/etcd
sudo chown etcd:etcd /var/lib/etcd

# Enable and start etcd
sudo systemctl enable etcd
sudo systemctl start etcd
```

### Verify etcd Cluster

```bash
# Check cluster health
etcdctl --endpoints=http://192.168.1.101:2379,http://192.168.1.102:2379,http://192.168.1.103:2379 endpoint health

# Expected output:
# http://192.168.1.101:2379 is healthy: successfully committed proposal: took = 2.345ms
# http://192.168.1.102:2379 is healthy: successfully committed proposal: took = 2.567ms
# http://192.168.1.103:2379 is healthy: successfully committed proposal: took = 2.123ms
```

## Part 4: Installing and Configuring Patroni

Patroni is a template for PostgreSQL HA solutions using Python. It handles failover, replication, and cluster management.

### Install Patroni on All Nodes

```bash
# Install dependencies
sudo apt install -y python3-pip python3-dev libpq-dev

# Install Patroni
sudo pip3 install patroni[etcd] psycopg2-binary

# Create Patroni configuration directory
sudo mkdir -p /etc/patroni
```

### Configure Patroni

Create Patroni configuration on **the primary node** first:

```bash
sudo tee /etc/patroni/patroni.yml <<EOF
scope: postgres-cluster
namespace: /db/
name: pg-primary

restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.1.101:8008

etcd3:
  hosts:
    - 192.168.1.101:2379
    - 192.168.1.102:2379
    - 192.168.1.103:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      parameters:
        max_connections: 100
        max_locks_per_transaction: 64
        max_worker_processes: 8
        max_prepared_transactions: 0
        wal_level: replica
        wal_log_hints: on
        track_commit_timestamp: off
        max_wal_senders: 10
        max_replication_slots: 10
        wal_keep_size: 1GB

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 192.168.1.0/24 md5
    - host all all 192.168.1.0/24 md5

  users:
    admin:
      password: admin_password
      options:
        - createrole
        - createdb
    replicator:
      password: replicator_password
      options:
        - replication

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.1.101:5432
  data_dir: /var/lib/postgresql/15/main
  bin_dir: /usr/lib/postgresql/15/bin
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: replicator_password
    superuser:
      username: postgres
      password: postgres_password
  parameters:
    unix_socket_directories: '/var/run/postgresql'

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF
```

**Important**: Change the passwords in the configuration above!

**⚠️ IMPORTANT SECURITY NOTE**: The configuration above contains placeholder passwords (`admin_password`, `replicator_password`, `postgres_password`). You MUST change these to strong, unique passwords before deploying to production!

For **replica nodes**, create similar configurations but adjust:

- `name`: pg-replica1 or pg-replica2
- `connect_address`: corresponding IP address
- Remove the `bootstrap` section (only primary needs it)

Example for replica1:

```bash
sudo tee /etc/patroni/patroni.yml <<EOF
scope: postgres-cluster
namespace: /db/
name: pg-replica1

restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.1.102:8008

etcd3:
  hosts:
    - 192.168.1.101:2379
    - 192.168.1.102:2379
    - 192.168.1.103:2379

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.1.102:5432
  data_dir: /var/lib/postgresql/15/main
  bin_dir: /usr/lib/postgresql/15/bin
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: replicator_password
    superuser:
      username: postgres
      password: postgres_password
  parameters:
    unix_socket_directories: '/var/run/postgresql'

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF
```

### Create Patroni Systemd Service

Create the service file on all nodes:

```bash
sudo tee /etc/systemd/system/patroni.service <<EOF
[Unit]
Description=Patroni PostgreSQL HA
After=syslog.target network.target

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/local/bin/patroni /etc/patroni/patroni.yml
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
TimeoutSec=30
Restart=no

[Install]
WantedBy=multi-user.target
EOF

# Set permissions
sudo chown postgres:postgres /etc/patroni/patroni.yml
sudo chmod 600 /etc/patroni/patroni.yml

# Ensure postgres user owns data directory
sudo chown -R postgres:postgres /var/lib/postgresql
```

### Start Patroni

Start on the **primary node first**:

```bash
sudo systemctl daemon-reload
sudo systemctl enable patroni
sudo systemctl start patroni

# Check status
sudo systemctl status patroni

# Watch Patroni logs
sudo journalctl -u patroni -f
```

Once the primary is running and initialized, start Patroni on the **replica nodes**:

```bash
# On pg-replica1 and pg-replica2
sudo systemctl daemon-reload
sudo systemctl enable patroni
sudo systemctl start patroni
```

### Verify Cluster Status

```bash
# Install patronictl wrapper
sudo pip3 install patroni[etcd]

# Check cluster status
patronictl -c /etc/patroni/patroni.yml list

# Expected output:
# + Cluster: postgres-cluster (7234567890123456789) -----+----+-----------+
# | Member      | Host          | Role    | State   | TL | Lag in MB |
# +-------------+---------------+---------+---------+----+-----------+
# | pg-primary  | 192.168.1.101 | Leader  | running |  1 |           |
# | pg-replica1 | 192.168.1.102 | Replica | running |  1 |         0 |
# | pg-replica2 | 192.168.1.103 | Replica | running |  1 |         0 |
# +-------------+---------------+---------+---------+----+-----------+
```

## Part 5: Setting Up HAProxy for Load Balancing

HAProxy will distribute read queries to replicas and route write queries to the primary.

### Install HAProxy

Install on a separate VM or on one of the nodes (we'll use a separate VM recommended):

```bash
sudo apt install -y haproxy keepalived
```

### Configure HAProxy

Edit `/etc/haproxy/haproxy.cfg`:

```bash
sudo tee /etc/haproxy/haproxy.cfg <<EOF
global
    maxconn 100
    log 127.0.0.1 local2

defaults
    log global
    mode tcp
    retries 2
    timeout client 30m
    timeout connect 4s
    timeout server 30m
    timeout check 5s

listen stats
    mode http
    bind *:7000
    stats enable
    stats uri /

listen primary
    bind *:5000
    option httpchk
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server pg-primary 192.168.1.101:5432 maxconn 100 check port 8008
    server pg-replica1 192.168.1.102:5432 maxconn 100 check port 8008 backup
    server pg-replica2 192.168.1.103:5432 maxconn 100 check port 8008 backup

listen replicas
    bind *:5001
    balance roundrobin
    option httpchk GET /replica
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server pg-replica1 192.168.1.102:5432 maxconn 100 check port 8008
    server pg-replica2 192.168.1.103:5432 maxconn 100 check port 8008
    server pg-primary 192.168.1.101:5432 maxconn 100 check port 8008 backup
EOF

# Restart HAProxy
sudo systemctl restart haproxy
sudo systemctl enable haproxy
```

### Connection Points

Now your applications can connect to:

- **Primary (writes)**: `haproxy-ip:5000`
- **Replicas (reads)**: `haproxy-ip:5001`
- **HAProxy Stats**: `http://haproxy-ip:7000`

## Part 6: Testing High Availability

### Test Failover

1. **Connect to the primary**:

   ```bash
   psql -h 192.168.1.101 -U postgres -d postgres
   ```

2. **Create a test database and table**:

   ```sql
   CREATE DATABASE testdb;
   \c testdb
   CREATE TABLE test_table (id SERIAL PRIMARY KEY, data TEXT, created_at TIMESTAMP DEFAULT NOW());
   INSERT INTO test_table (data) VALUES ('Test data before failover');
   ```

3. **Stop the primary node**:

   ```bash
   # On pg-primary
   sudo systemctl stop patroni
   ```

4. **Watch automatic failover**:

   ```bash
   # On any node
   patronictl -c /etc/patroni/patroni.yml list

   # You should see one replica promoted to leader
   ```

5. **Verify data on the new primary**:

   ```bash
   psql -h <new-primary-ip> -U postgres -d testdb
   SELECT * FROM test_table;
   ```

6. **Restart the old primary** (it will rejoin as a replica):

   ```bash
   sudo systemctl start patroni
   ```

## Part 7: Monitoring and Maintenance

### Monitoring Patroni REST API

Each node exposes a REST API on port 8008:

```bash
# Check node health
curl http://192.168.1.101:8008/health

# Check if node is primary
curl http://192.168.1.101:8008/primary

# Check if node is replica
curl http://192.168.1.102:8008/replica
```

### Useful Patroni Commands

```bash
# List cluster members
patronictl -c /etc/patroni/patroni.yml list

# Failover to specific node
patronictl -c /etc/patroni/patroni.yml failover

# Switchover (planned failover)
patronictl -c /etc/patroni/patroni.yml switchover

# Restart a node
patronictl -c /etc/patroni/patroni.yml restart postgres-cluster pg-replica1

# Reload configuration
patronictl -c /etc/patroni/patroni.yml reload postgres-cluster
```

### Monitoring Best Practices

Consider integrating with monitoring solutions:

- **Prometheus + Grafana**: Use postgres_exporter and haproxy_exporter
- **pgBadger**: Analyze PostgreSQL logs
- **Check_patroni**: Nagios/Icinga plugin for Patroni monitoring

### Backup Strategy

Implement regular backups:

```bash
# Install pgBackRest
sudo apt install -y pgbackrest

# Or use pg_basebackup for simple backups
pg_basebackup -h 192.168.1.101 -U replicator -D /backup/postgres -Fp -Xs -P
```

Consider automated backup solutions:

- **pgBackRest**: Full, incremental, and differential backups
- **Barman**: Backup and recovery manager
- **WAL-G**: Archive and restore PostgreSQL backups

## Part 8: Security Hardening

### Firewall Configuration

Configure firewall rules on all nodes:

```bash
# PostgreSQL
sudo ufw allow from 192.168.1.0/24 to any port 5432

# Patroni REST API
sudo ufw allow from 192.168.1.0/24 to any port 8008

# etcd
sudo ufw allow from 192.168.1.0/24 to any port 2379
sudo ufw allow from 192.168.1.0/24 to any port 2380

# Enable firewall
sudo ufw enable
```

### SSL/TLS Configuration

For production, enable SSL:

1. **Generate SSL certificates** (use Let's Encrypt or internal CA)

2. **Configure PostgreSQL SSL**:

   ```yaml
   # In patroni.yml, add under postgresql.parameters:
   ssl: 'on'
   ssl_cert_file: '/etc/ssl/certs/server.crt'
   ssl_key_file: '/etc/ssl/private/server.key'
   ssl_ca_file: '/etc/ssl/certs/ca.crt'
   ```

3. **Update pg_hba.conf** to require SSL (restrict to your specific network):

   ```
   # Only allow SSL connections from your network
   hostssl all all 192.168.1.0/24 md5
   # For VPN or specific remote access, add specific IP ranges
   # hostssl all all 10.0.0.0/8 md5
   ```

## Performance Tuning

### PostgreSQL Configuration Tuning

Adjust based on your workload and resources:

```yaml
# In patroni.yml under postgresql.parameters:
shared_buffers: '1GB'                    # 25% of RAM
effective_cache_size: '3GB'              # 75% of RAM
maintenance_work_mem: '256MB'
checkpoint_completion_target: 0.9
wal_buffers: '16MB'
default_statistics_target: 100
random_page_cost: 1.1                    # For SSD
effective_io_concurrency: 200            # For SSD
work_mem: '10MB'
min_wal_size: '1GB'
max_wal_size: '4GB'
```

### Proxmox VM Optimization

- **Enable VirtIO drivers** for better disk and network performance
- **Use VirtIO SCSI** for disk controllers
- **Enable QEMU Guest Agent** for better VM management
- **Allocate dedicated CPU cores** if possible
- **Use local storage** or high-performance shared storage

## Troubleshooting Common Issues

### Patroni Won't Start

```bash
# Check logs
sudo journalctl -u patroni -n 50

# Common issues:
# - Permission issues with data directory
# - etcd not accessible
# - Port conflicts
```

### Replication Lag

```bash
# Check replication status on primary
psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Check lag on replicas
psql -U postgres -c "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;"
```

### Split-Brain Prevention

Patroni prevents split-brain using DCS (etcd). Ensure:

- Odd number of etcd nodes (3, 5, 7)
- Stable network connection between nodes
- Proper TTL and loop_wait settings

## Conclusion

You now have a production-ready PostgreSQL high availability cluster running on Proxmox! This setup provides:

✅ **Automatic failover** - No manual intervention needed when primary fails
✅ **Load balancing** - Distribute read queries across replicas
✅ **Zero downtime maintenance** - Perform rolling updates
✅ **Data durability** - Multiple synchronized copies of your data
✅ **Scalability** - Easy to add more read replicas

### Next Steps

Consider these enhancements:

- **Add more replicas** for increased read capacity
- **Implement pgBouncer** for connection pooling
- **Set up monitoring** with Prometheus and Grafana
- **Configure automated backups** with pgBackRest
- **Implement point-in-time recovery** (PITR)
- **Add Consul** as an alternative to etcd
- **Deploy across multiple Proxmox nodes** for true fault tolerance

### Additional Resources

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Patroni Documentation](https://patroni.readthedocs.io/)
- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [HAProxy Documentation](https://www.haproxy.org/documentation.html)
- [etcd Documentation](https://etcd.io/docs/)

### Final Thoughts

Building a highly available database infrastructure might seem complex, but with tools like Patroni and Proxmox, it's more accessible than ever. This setup is production-ready and can scale with your needs.

Remember to:

- **Test your failover procedures** regularly
- **Monitor your cluster** continuously
- **Keep backups** offsite and test restores
- **Document your procedures** and runbooks
- **Stay updated** with security patches

Happy clustering! 🐘🚀

---

*Have questions or suggestions? Feel free to reach out or leave a comment below.*
