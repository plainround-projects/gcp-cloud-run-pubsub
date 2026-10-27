#!/usr/bin/env bash
# Step 6: put the role back (Terraform owns it), then replay the dead-lettered message by publishing its payload again.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" --member="serviceAccount:$WORKER_SA" --role=roles/storage.objectCreator
echo "waiting 60 seconds for the grant to apply"
sleep 60

DATA="$(gcloud pubsub subscriptions pull uploads-dead-pull --auto-ack --limit=1 --format='value(message.data)')"
: "${DATA:?no message in the dead-letter subscription}"
# The CLI prints the payload decoded; publish it again to the main topic.
gcloud pubsub topics publish uploads --message="$DATA"
sleep 15
gcloud storage ls "gs://$BUCKET/results/"
