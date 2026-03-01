import pandas as pd
import json
import os

input_path = "assets/excel/[7372] Parepare (Sudah GC).xlsx"
output_path = "assets/json/parepare_comparison.json"

try:
    df = pd.read_excel(input_path)
    
    # Convert all columns to string to avoid serialization issues
    df = df.astype(str)
    
    # Replace 'nan' with empty string
    df = df.replace('nan', '')
    
    records = df.to_dict(orient='records')
    
    with open(output_path, 'w') as f:
        json.dump(records, f, indent=2)
        
    print(f"Successfully converted {len(records)} records to {output_path}")
    
except Exception as e:
    print(f"Error: {e}")
