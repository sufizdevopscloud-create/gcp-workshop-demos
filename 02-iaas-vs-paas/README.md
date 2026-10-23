# Demo 2 · IaaS vs PaaS

**One sentence:** run the same tiny web page two ways, as a virtual machine you manage (IaaS) and as a Cloud Run container Google manages (PaaS), and count who makes more decisions.

## What we are doing, and why

Noon App needs a web page. Option A is a **virtual machine**: you pick the size, pick and patch the operating system, install nginx, open the firewall, and you scale it. Option B is **Cloud Run**: you hand over a container and Google does everything underneath. The demo puts both side by side so students *see* the difference in responsibility, not just read about it.

## What gets created

| Resource | What it is |
|---|---|
| `demo-vpc`, `demo-subnet`, `demo-allow-http` | A small network and a firewall rule that lets port 80 in |
| `noon-iaas-vm` | The IaaS side: an e2-small VM that installs nginx when it boots |
| `noon-paas-service` | The PaaS side: a Cloud Run service running Google's sample container, 0 to 5 instances |

## Run it

```bash
cd 02-iaas-vs-paas
terraform init
terraform apply -var project_id=$PROJECT
terraform output
```

Takes about 2 minutes. The VM needs another minute to install nginx after Terraform finishes.

## Check it in the console

1. **Compute Engine > VM instances**: `noon-iaas-vm` is running and billing by the second. Open its external IP (`terraform output iaas_url`).
2. **Cloud Run**: `noon-paas-service` shows **0 instances** when idle, so it costs nothing right now.
3. Run `$(terraform output -raw paas_curl)`. A browser shows 403 because the service is private by default (a good security point); the command sends your identity token.

## What to explain

- IaaS: you own the OS, patches, web server, scaling and the security of the machine. Google owns the hardware and data centre.
- PaaS: you own the container. Google owns servers, OS, patching, scaling and load balancing.
- Ask: which one for a new web API, and which for an old application that needs a specific operating system?

## Clean up

```bash
terraform destroy -var project_id=$PROJECT
```

Cost: a few cents per hour while the VM runs.
