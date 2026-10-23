# Live demos for Day 1

The site shows three of these on Day 1 (IaaS vs PaaS, networking, security). `01-cloud-computing` is kept here as a spare: it is no longer on the site, to keep the Cloud computing page short.

Four small Terraform projects, one per topic. Each one is a use case you can apply in about two minutes and destroy straight afterwards.

| Folder | Topic | What you show |
|---|---|---|
| `01-cloud-computing` | Cloud computing | A web page that costs nothing while nobody visits (Cloud Run scales to zero) and a bucket that grows on demand |
| `02-iaas-vs-paas` | GCP services | The same page as a virtual machine (IaaS) and as Cloud Run (PaaS): count who manages what |
| `03-networking` | Networking | VPC, subnets, firewall rules, private servers, IAP access, Cloud NAT with a fixed address |
| `04-security` | Security | Least-privilege identity, your own encryption key, a bucket that cannot be public, a secret, audit logs |

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

Per demo, what to open in the console is on the demo's page of the workshop site: https://learn.sufizdevops.com/gcp/services (demo 1), /gcp/networking (demo 2) and /gcp/security (demo 3).

## Region

The demos run in **Mumbai (`asia-south1`, zone `asia-south1-a`)**. The Dammam region (`me-central2`) may not be available to a new or trial billing account, and asking for it then fails with `LOCATION_POLICY_VIOLATED`. To use another region, add `-var region=... -var zone=...`.

## Cost and safety

- Everything is small (e2-small machines, scale-to-zero containers, a few kilobytes of storage) and costs cents if destroyed within the hour. Cloud NAT and a reserved IP in demo 3 are charged by the hour while they exist.
- Always run `terraform destroy` after the demo.
- Demo 1 is private by default. If your organization allows public access, add `-var allow_public=true` so students can open the page.
- If you apply the landing zone first, its organization policies (no external IPs, no public access, no default network) will block parts of demos 1 and 2 in projects under that organization. Run these demos in a project outside it, or use the private options shown in the outputs.

## Check without a cloud account

```bash
cd demos/01-cloud-computing && terraform init -backend=false && terraform validate
```
