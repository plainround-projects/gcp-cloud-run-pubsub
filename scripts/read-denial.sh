#!/usr/bin/env bash
# Step 5, the evidence: the permission-denied entry in the worker's log, and the message in the dead-letter subscription.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

echo "== the denial in the worker's log (account, permission, resource)"
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="worker" AND severity>=ERROR' \
  --limit=5 --freshness=1h --format='value(jsonPayload.error)'

echo "== the message in the dead-letter subscription (source subscription and delivery attempts)"
gcloud pubsub subscriptions pull uploads-dead-pull --limit=1 \
  --format='value(message.attributes.CloudPubSubDeadLetterSourceSubscription, message.deliveryAttempt, message.data)'
echo "(not acknowledged here, so scripts/restore-and-replay.sh can still read it)"
