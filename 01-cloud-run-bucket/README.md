# Demo 1 · Cloud Run and a bucket

**One sentence:** put a sale landing page on Cloud Run and its images in a Cloud Storage bucket, in about two minutes, with nothing to buy, install or pay for while nobody visits.

## What we are doing, and why

Noon App wants a pop-up page for the National Day sale. This is cloud computing at its simplest. **Cloud Run** runs a container and scales it to zero when there are no visitors, so you pay only while requests are handled. A **bucket** stores files of any size, with a rule that deletes them after 30 days, because the sale will be over. Together they show the two ideas of cloud computing: pay for use, and elastic capacity.

## What gets created

| Resource | What it is |
|---|---|
| `noon-sale-popup` | A Cloud Run service (Google's sample container), 0 to 5 instances |
| `<project>-noon-sale-assets` | A bucket, public access blocked, files deleted after 30 days |
| `sale-banner.txt` | One sample file in the bucket |

## Run it

```bash
cd 01-cloud-run-bucket
terraform init
terraform apply -var project_id=$PROJECT
terraform output
```

Takes about 1 to 2 minutes.

## Check it in the console

1. **Cloud Run > noon-sale-popup**: the URL, the **Revisions** tab, and **0 instances** while idle.
2. Run the `try_it` command from the output. A browser shows **403** because new organizations keep Cloud Run private; the command sends your identity token and prints the page. To make it public instead: `terraform apply -var project_id=$PROJECT -var allow_public=true` (only works if your organization allows it).
3. **Cloud Storage**: open the bucket, see `sale-banner.txt`, and the **Lifecycle** tab with the 30-day delete rule.

## What to explain

- Nothing was bought or installed. It exists, it works, and with no visitors it costs nothing.
- `max_instance_count = 5` is a ceiling so a surprise cannot become a surprise bill.
- The bucket cannot be made public (`public_access_prevention`), a quiet security default.

## Clean up

```bash
terraform destroy -var project_id=$PROJECT
```

Cost: cents (storage is a few bytes, Cloud Run is free when idle).
