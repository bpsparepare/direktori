import json

def verify_geojson(original_path, optimized_path):
    print(f"Verifying optimized GeoJSON...")
    print(f"Original: {original_path}")
    print(f"Optimized: {optimized_path}")
    
    try:
        with open(original_path, 'r', encoding='utf-8') as f:
            orig_data = json.load(f)
            
        with open(optimized_path, 'r', encoding='utf-8') as f:
            opt_data = json.load(f)
            
    except Exception as e:
        print(f"Error reading files: {e}")
        return

    orig_features = orig_data.get('features', [])
    opt_features = opt_data.get('features', [])
    
    print(f"\n1. Feature Count Check:")
    print(f"   Original: {len(orig_features)}")
    print(f"   Optimized: {len(opt_features)}")
    
    if len(orig_features) != len(opt_features):
        print("   ❌ COUNT MISMATCH!")
    else:
        print("   ✅ Count matches.")

    print(f"\n2. ID Completeness Check (idsls):")
    orig_ids = set()
    for f in orig_features:
        props = f.get('properties', {})
        if props and 'idsls' in props:
            orig_ids.add(props['idsls'])
            
    opt_ids = set()
    for f in opt_features:
        props = f.get('properties', {})
        if props and 'idsls' in props:
            opt_ids.add(props['idsls'])
            
    missing_ids = orig_ids - opt_ids
    if missing_ids:
        print(f"   ❌ MISSING IDs in optimized file: {len(missing_ids)}")
        print(f"   Example missing: {list(missing_ids)[:5]}")
    else:
        print("   ✅ All IDs present.")
        
    print(f"\n3. Geometry Validity Check:")
    invalid_geom_count = 0
    for i, f in enumerate(opt_features):
        geom = f.get('geometry')
        if not geom or 'coordinates' not in geom or not geom['coordinates']:
            # Check if original also had empty geometry
            orig_geom = orig_features[i].get('geometry')
            if orig_geom and 'coordinates' in orig_geom and orig_geom['coordinates']:
                 print(f"   ❌ Feature {i} (ID: {f.get('properties', {}).get('idsls')}) has LOST geometry!")
                 invalid_geom_count += 1
            else:
                 # Original was also empty, so this is expected
                 pass
                 
    if invalid_geom_count == 0:
        print("   ✅ All geometries preserved (or originally empty).")
    else:
        print(f"   ❌ {invalid_geom_count} geometries lost/corrupted.")

    print("\nVerification Complete.")

if __name__ == "__main__":
    original = '/Users/nasrul/flutter/direktori/assets/geojson/final_sls.geojson'
    optimized = '/Users/nasrul/flutter/direktori/assets/geojson/final_sls_optimized.json'
    verify_geojson(original, optimized)
