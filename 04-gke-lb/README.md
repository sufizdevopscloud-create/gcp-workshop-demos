# Demo 4 · A GKE cluster running a small app behind a load balancer

**One sentence:** create a Kubernetes cluster with GKE Autopilot, run three copies of a small app on it, and put a load balancer with one public address in front.

## What we are doing, and why

The Noon App API runs as containers, and containers need something to run, restart and scale them: that is **Kubernetes**. **GKE** is Google's managed Kubernetes; in **Autopilot** mode Google also manages the machines, so you only say how much CPU and memory each copy needs. The demo shows the Kubernetes ideas that matter most:

- A **Deployment** says “keep 3 copies (pods) of this container running”. If one dies, Kubernetes starts another.
- A **Service of type LoadBalancer** asks Google Cloud for a load balancer and a public address, and spreads requests across the pods.

```
internet -> load balancer (Kubernetes Service) -> 3 pods of hello-app
```

## What gets created

| Resource | What it is |
|---|---|
| `gke-vpc`, `gke-subnet` | A private network with ranges for pods and services |
| `gke-nodes` service account | The identity of the machines, with the one role they need |
| `noon-autopilot` | The GKE Autopilot cluster in Mumbai, private nodes (no public IPs) |
| `hello-app` Deployment | 3 pods of Google's sample app, which prints its own pod name |
| `hello-lb` Service | The load balancer and its public address |

## Run it

```bash
cd 04-gke-lb
terraform init
terraform apply -var project_id=$PROJECT
terraform output
```

**The cluster takes about 8 to 12 minutes to create.** Start this demo first and talk about other things while it builds. The load balancer address appears at the end.

## Check it in the console

1. **Kubernetes Engine > Clusters > `noon-autopilot`**: an Autopilot cluster, no node pools to manage.
2. **Kubernetes Engine > Workloads > `hello-app`**: 3 pods running.
3. **Kubernetes Engine > Services & Ingress > `hello-lb`**: the external address.
4. Run the loop from `terraform output try_it`: the **Hostname** changes between requests (that is the pod name).

From your terminal, connect and look at it the way engineers do:

```bash
$(terraform output -raw connect_kubectl)
kubectl get pods -o wide
kubectl delete pod -l app=hello-app --wait=false
kubectl get pods
```

## The moment to remember

Delete the pods with the last command and run `kubectl get pods` again: Kubernetes has already started new ones to get back to three. You declared what you want, and it keeps making it true.

## What to explain

- Cloud Run vs GKE: Cloud Run is simpler for one container. GKE gives control for many microservices.
- Autopilot vs Standard: Autopilot bills for the CPU and memory the pods request and Google manages nodes; Standard gives you node pools to tune.
- The Terraform file has two halves: Google Cloud things (network, cluster) and Kubernetes things (deployment, service).

## Clean up

```bash
terraform destroy -var project_id=$PROJECT
```

Destroy takes a few minutes: the load balancer is removed first, then the cluster. Cost: roughly 15 to 20 cents per hour while it exists (the cluster fee is covered by the monthly free credit of one Autopilot or Standard cluster per billing account, but the pods and the load balancer are not).
