import json
import os
from kafka import KafkaConsumer, KafkaProducer

# Configure Kafka
bootstrap_servers = 'kafka.default.svc.cluster.local:9092'
topic = 'website.events'
dlq_topic = 'website.events.dlq'

# Initialize Consumer (Group: notify)
consumer = KafkaConsumer(
    topic,
    bootstrap_servers=bootstrap_servers,
    group_id='notify',
    auto_offset_reset='earliest',
    enable_auto_commit=True
)

# Initialize Producer for Dead Letter Queue
dlq_producer = KafkaProducer(bootstrap_servers=bootstrap_servers)

# In-memory store for idempotency (in production, use Redis or a Database)
processed_events = set()

print(f"👂 Consumer Group 'notify' started. Listening to topic: {topic}")

for message in consumer:
    try:
        # Decode the JSON payload
        event = json.loads(message.value.decode('utf-8'))
        tenant = event.get('tenant')
        sha = event.get('sha')
        event_type = event.get('event')
        
        # 1. Idempotency Check: (tenant, sha)
        event_key = f"{tenant}-{sha}"
        if event_key in processed_events:
            print(f"⏭️ Skipping duplicate event: {event_key}")
            continue
            
        # 2. Simulate processing (e.g., sending a Slack notification)
        if event_type == 'WebsiteCreated':
            print(f"✅ Slack/Email Sent: Website created for {tenant} (SHA: {sha})")
        else:
            print(f"⚠️ Unknown event: {event_type}")
            
        # Mark as processed
        processed_events.add(event_key)
        
    except Exception as e:
        # 3. Dead Letter Queue (DLQ) on failure
        print(f"❌ Failed to process message: {e}")
        print(f"📦 Routing to Dead Letter Topic: {dlq_topic}")
        dlq_producer.send(dlq_topic, message.value)
        dlq_producer.flush()