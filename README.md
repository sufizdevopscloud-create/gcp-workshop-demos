# Live demos for Day 1

Six small Terraform projects, numbered in the order we teach them. Each folder has its own `README.md` that explains **what the demo does, why, what gets created, what to check in the console and how to clean up**. Each one is a use case you can apply in a few minutes and destroy straight afterwards.

| Folder | Topic | What it shows | Apply time |
|---|---|---|---|
| [`01-cloud-run-bucket`](01-cloud-run-bucket) | Cloud computing | A sale page on Cloud Run that scales to zero, and a bucket for its files: no servers, pay for use | 2 min |
| [`02-iaas-vs-paas`](02-iaas-vs-paas) | GCP services | The same page as a virtual machine (IaaS) and as Cloud Run (PaaS): count who manages what | 2 min |
| [`03-vm-mig-lb`](03-vm-mig-lb) | GCP services | VMs in a managed instance group across zones, auto-healing and auto-scaling, behind one load balancer | 4 min + 4 min for the load balancer |
| [`04-gke-lb`](04-gke-lb) | GCP services | A GKE Autopilot cluster running three copies of an app behind a load balancer | 10 min |
| [`05-networking`](05-networking) | Networking | VPC, subnets, firewall rules, private servers, IAP access, Cloud NAT with a fixed address | 4 min |
| [`06-security`](06-security) | Security | Least-privilege identity, your own encryption key, a bucket that cannot be public, a secret, audit logs | 3 min |

Demos 2, 3 and 4 are one story, the **compute ladder**: a virtual machine you manage, virtual machines in a group that heal and scale, containers on Kubernetes, and Cloud Run with nothing to manage. Start 3 and 4 early, because they take the longest to build.

## Run a demo from scratch

**1. Check the tools** (gcloud, Terraform and git must all print a version):

```bash
gcloud --version && terraform version && git --version
```

**2. Log in** with the account that owns your sandbox project. Both commands open a browser, once. On the permissions page, tick **Select all**.

```bash
gcloud auth login                              # your Google account, for gcloud commands
gcloud auth application-default login          # the same account, for Terraform
gcloud config list                             # check the account is the one you meant
```

**3. Pick your sandbox project** and tell Terraform's login which project to bill:

```bash
export PROJECT=YOUR_PROJECT_ID               # your own project id
gcloud config set project $PROJECT
gcloud auth application-default set-quota-project $PROJECT
```

**4. Get the code and open the demo** (students: clone the repository, then change into the demo folder):

```bash
git clone https://github.com/sufizdevopscloud-create/gcp-workshop-demos.git
cd gcp-workshop-demos/02-iaas-vs-paas
ls && cat main.tf                              # read the code before you run it
```

**5. Run it.** `plan` shows what will be created and changes nothing. `apply` creates it after you type `yes`.

```bash
terraform init
terraform plan  -var project_id=$PROJECT
terraform apply -var project_id=$PROJECT
terraform output                               # the addresses and commands to try
```

**6. Check it in the console**, explain it, then clean up:

```bash
terraform destroy -var project_id=$PROJECT
```

Per demo, what to open in the console is on the demo's page of the workshop site: https://learn.sufizdevops.com/gcp/computing (demo 1), /gcp/services (demos 2 to 4), /gcp/networking (demo 5) and /gcp/security (demo 6).

## Region

The demos run in **Mumbai (`asia-south1`, zone `asia-south1-a`)**. The Dammam region (`me-central2`) may not be available to a new or trial billing account, and asking for it then fails with `LOCATION_POLICY_VIOLATED`. To use another region, add `-var region=... -var zone=...`.

## Cost and safety

- Everything is small (e2-small machines, scale-to-zero containers, a few kilobytes of storage). Each demo costs cents if destroyed within the hour; demos 3 and 4 are the largest, roughly 10 to 20 cents per hour each. Cloud NAT, the reserved IP, the load balancers and the GKE cluster are charged by the hour while they exist, so destroy them.
- Always run `terraform destroy` after the demo.
- Cloud Run is private by default in new organizations, so opening its address in a browser shows 403. Demos 1 and 2 print a `curl` command that sends your identity token and proves it works.
- If you apply the landing zone first, its organization policies (no external IPs, no public access, no default network) will block parts of demos 2, 3 and 5 in projects under that organization. Run these demos in a project outside it, or use the private options shown in the outputs.

## Check without a cloud account

```bash
cd 02-iaas-vs-paas && terraform init -backend=false && terraform validate
```

## Running several at once

Demos 3 and 4 take the longest, so on the day start them in two spare terminals (each in its own folder) and keep teaching. They use separate networks and do not collide. The project allows 5 networks and the default one counts, so running demos 2 to 5 together uses exactly five; destroy one before starting another.
