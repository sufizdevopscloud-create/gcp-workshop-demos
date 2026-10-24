# Demo 5 · Networking

**One sentence:** build a private network where a web server and a database server have no public IP addresses, only the right doors are open, and the servers reach the internet from one fixed address.

## What we are doing, and why

Noon App has a web tier and a database tier. In a real company the database must never be reachable from the internet, and an admin must be able to log in without an SSH port open to the world. This demo builds exactly that, so students see the four building blocks (VPC, subnets, routes, firewall rules) as real objects, and the difference between **north-south** traffic (in and out of the network) and **east-west** traffic (between servers inside it).

## What gets created

| Resource | What it is |
|---|---|
| `noon-vpc` with a `web` and a `db` subnet | The private network and its two rooms |
| `allow-iap-ssh` firewall rule | Lets admins in through Identity-Aware Proxy only (no SSH from the internet) |
| `allow-web-to-db` firewall rule | East-west: servers tagged `web` may reach servers tagged `db` on port 8080 only |
| Cloud Router, Cloud NAT and a reserved IP | Lets private servers go out to the internet from one fixed address |
| `web-vm`, `db-vm` | Two small VMs with **no public IP**, using OS Login |

## Run it

```bash
cd 05-networking
terraform init
terraform apply -var project_id=$PROJECT
terraform output
```

Takes about 3 to 4 minutes.

## Check it in the console

**VPC network**: open `noon-vpc`, then its **Subnets**, **Routes** and **Firewall rules** tabs, and **Network services > Cloud NAT**. Then SSH in without any public address:

```bash
gcloud compute ssh web-vm --zone asia-south1-a --tunnel-through-iap --project $PROJECT
```

On the web VM, run the three commands from `terraform output try_from_web_vm`.

## What to explain

- First command: the web VM calls the database on port 8080 and gets “hello from the database tier”. Allowed by `allow-web-to-db`.
- Second command: the same VM tries port 22 on the database. It **times out**. No rule allows it, so the default is deny.
- Third command: `ifconfig.me` prints the NAT address. That is the single address a partner would put on their allow-list.
- **The moment to remember:** delete the firewall rule `allow-web-to-db` in the console and run the first command again. It now fails.

## Clean up

```bash
terraform destroy -var project_id=$PROJECT
```

Cost: the NAT gateway and reserved IP bill by the hour, so do not leave this running overnight.
