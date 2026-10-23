# Demo 6 · Security

**One sentence:** protect a bucket of customer invoices with five layers of defence, then try to break them.

## What we are doing, and why

Noon App stores invoices. Security is not one switch; it is layers, so one mistake does not expose everything. Each resource in the code is one layer, and the demo ends with students attacking their own work and watching it fail.

| Layer | Resource | What it does |
|---|---|---|
| Identity | service account `invoice-reader` | Can read this one bucket and nothing else (least privilege) |
| Encryption | Cloud KMS key ring and key | The bucket is encrypted with **your own key** (CMEK), rotated every 90 days |
| Exposure | bucket with `public_access_prevention = enforced` | Nobody, even an owner, can make it public |
| Secrets | Secret Manager secret | The database password lives here, readable only by the app's identity, never in code |
| Detection | project audit-log configuration | Every read and write of data is recorded |

## Run it

```bash
cd 06-security
terraform init
terraform apply -var project_id=$PROJECT
terraform output try_to_break_it
```

Takes about 2 to 3 minutes.

## Check it in the console

1. **IAM**: find `invoice-reader` and show it has no project-wide role.
2. **Security > Key Management**: the key ring, the key and its 90-day rotation.
3. **Cloud Storage**: the bucket, its **Protection** tab (public access prevention on) and its encryption key.
4. **Security > Secret Manager**: the secret and who may read it.

## The moment to remember

Run the `make_it_public` command from `try_to_break_it`. It is **refused**. Then open **Logging > Logs Explorer** (filter on the bucket) and, within a minute, find your own failed attempt in the audit log.

## What to explain

- If someone steals the service account, what can they do? Read invoices, and nothing else.
- Encryption with your own key means you can cut off access by disabling the key.
- Preventive controls (can't make it public) and detective controls (audit logs) work together.

## Clean up

```bash
terraform destroy -var project_id=$PROJECT
```

KMS keys are scheduled for deletion rather than removed instantly, and the key ring name is random each run, so repeated runs do not collide. Cost: cents.
