import json
import csv
import os
import sys

# Increase CSV field size limit just in case
csv.field_size_limit(sys.maxsize)

input_path = r'd:\flutter\direktori\assets\json\data-gc.json'
output_dir = r'd:\flutter\direktori\assets\csv'
output_path = os.path.join(output_dir, 'data-gc.csv')

if not os.path.exists(output_dir):
    os.makedirs(output_dir)

print(f"Loading JSON from {input_path}...")
try:
    with open(input_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
except Exception as e:
    print(f"Error reading JSON: {e}")
    exit(1)

if not data:
    print("No data found.")
    exit()

print(f"Loaded {len(data)} records. analyzing keys...")

# Get all keys from all records to ensure complete schema
keys = set()
for item in data:
    if isinstance(item, dict):
        keys.update(item.keys())

fieldnames = sorted(list(keys))
print(f"Found {len(fieldnames)} columns: {', '.join(fieldnames)}")

print(f"Writing CSV to {output_path}...")
try:
    with open(output_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        
        # Write rows in batches to show progress
        batch_size = 1000
        total = len(data)
        for i in range(0, total, batch_size):
            batch = data[i:i+batch_size]
            writer.writerows(batch)
            if (i + batch_size) % 10000 == 0:
                print(f"Written {i + batch_size}/{total} records...", end='\r')
                
    print(f"\nConversion complete. Saved to {output_path}")
except Exception as e:
    print(f"Error writing CSV: {e}")
    exit(1)
