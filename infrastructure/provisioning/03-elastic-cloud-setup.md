# infrastructure/provisioning/03-elastic-cloud-setup.md
#
# Elastic Stack setup — using Elastic Cloud (managed) instead of self-hosting
# on the cluster. This is faster (minutes vs hours) and is what the
# assessment expects functionally (Elasticsearch + Kibana + APM Server +
# Fleet). Azure also has an "Elastic Cloud (Azure Native ISV Service)"
# Marketplace listing if you'd rather it bill through your Azure
# subscription directly — either path works, steps below are for the
# standalone Elastic Cloud trial since it's the fastest to get running.

## Steps

1. Go to https://cloud.elastic.co/registration and sign up for the free trial
   (no card required for the trial period).
2. Once logged in, click **Create deployment**.
   - Choose a cloud provider/region (pick one close to you, e.g. Azure
     South Africa if listed, otherwise any region — latency doesn't matter
     much for this assessment).
   - Use the default "Elasticsearch" deployment template — it includes
     Kibana and the APM/Fleet integrations already.
3. Wait ~5 minutes for the deployment to provision. You'll be shown:
   - **Elasticsearch endpoint URL**
   - **Kibana URL**
   - **Username/password** (save these immediately — password is shown once)
4. Log into Kibana using the URL and credentials.
5. In Kibana, go to **Observability -> APM -> Settings -> Fleet-managed** (or
   search "APM" in the top search bar). Kibana will offer to set up the
   integration via Fleet automatically:
   - This creates an **APM Server** and gives you an **OTLP intake endpoint**
     (this is the `ELASTIC_APM_SERVER_URL` used in `values-gateway.yaml`)
     and a **secret token** (`ELASTIC_APM_SECRET_TOKEN`).
6. Also note down, from Kibana -> Stack Management -> API Keys, an API key
   or use the same secret token for the Beats/Elastic Agent configs in
   `infrastructure/` — save both endpoint + credentials somewhere safe,
   e.g. a local `.env` file (DO NOT commit this to Git).

## What you'll walk away with (fill these in for your own reference — do not commit real values)

```
ELASTICSEARCH_HOST=https://<your-deployment>.es.<region>.azure.elastic-cloud.com
KIBANA_URL=https://<your-deployment>.kb.<region>.azure.elastic-cloud.com
ELASTIC_APM_SERVER_URL=https://<your-deployment>.apm.<region>.azure.elastic-cloud.com
ELASTIC_APM_SECRET_TOKEN=<from Kibana APM setup>
ES_USER=elastic
ES_PASSWORD=<shown once at deployment creation>
```

These four values are what everything else in this repo (`values-gateway.yaml`,
the Postgres/Redis/NGINX Beats configs, the Fleet agent enrollment) plugs into.
