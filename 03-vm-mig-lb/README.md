# Demo 3 · Virtual machines in a managed instance group behind a load balancer

**One sentence:** run several identical VMs in different zones, replace any that fail, add more when busy, and give them all one address with a load balancer.

## What we are doing, and why

One server is a single point of failure and a ceiling. The Noon App web tier must survive a server dying and must grow on sale day. The standard Compute Engine answer is a **managed instance group (MIG)**: you write one recipe for a VM (the *instance template*) and Google keeps the right number of copies running. A **load balancer** puts one public address in front of them. The VMs themselves have **no public IP**: only the load balancer and its health checks can reach them.

```
internet -> load balancer (one address) -> health check -> 2 to 4 identical VMs in different zones
```

## What gets created

| Resource | What it is |
|---|---|
| `mig-vpc`, `mig-subnet`, Cloud NAT | A private network; NAT lets the VMs download nginx without public addresses |
| `mig-allow-lb-and-health-checks` firewall rule | Only Google's load balancer ranges may reach port 80 |
| Instance template `noon-web-*` | The recipe for one VM: e2-small, Debian 12, installs nginx, shows its own name and zone |
| `noon-web-mig` | The regional MIG: copies spread across zones, **auto-healing** by health check |
| `noon-web-autoscaler` | Between 2 and 4 VMs, adding more above 60% CPU |
| `noon-web-ip`, backend service, URL map, HTTP proxy, forwarding rule | The global external load balancer and its single address |

## Run it

```bash
cd 03-vm-mig-lb
terraform init
terraform apply -var project_id=$PROJECT
terraform output
```

Terraform finishes in about 3 to 5 minutes. **The load balancer then takes another 3 to 5 minutes to start answering**; until then you see a 502 error or a timeout. That is normal. Start this demo early.

## Check it in the console

1. **Compute Engine > Instance groups > `noon-web-mig`**: two VMs, in different zones, no external IP.
2. **Network services > Load balancing > `noon-web-url-map`**: the frontend address, the backend service and the health status of each VM.
3. Refresh the page at `load_balancer_url` or run the loop from `terraform output wait_then_try`: the VM name changes between requests. That is the load balancer at work.

## The moment to remember

Delete one VM (**Instance groups > noon-web-mig > select a VM > Delete**) while the loop runs. The site keeps answering from the other VM, and a few minutes later the MIG creates a replacement by itself. Nobody was paged.

## What to explain

- Why a MIG and not two hand-made VMs: identical copies, auto-healing, auto-scaling, rolling updates.
- Why spread over zones: a failure of one building does not take the site down.
- Why no public IP on the VMs: less to attack. Only the load balancer is exposed.
- Compare with demo 2: the VMs are still IaaS (you patch them), but you stopped treating them as pets.

## Clean up

```bash
terraform destroy -var project_id=$PROJECT
```

Cost: roughly 10 to 15 cents per hour (2 to 4 VMs, NAT and the load balancer's forwarding rule).
