import json
import os

def optimize_geojson(input_path, output_path):
    print(f"Reading {input_path}...")
    try:
        with open(input_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        print(f"Error reading input file: {e}")
        return

    if 'features' not in data:
        print("Error: No 'features' key found in GeoJSON.")
        return

    features = data['features']
    print(f"Found {len(features)} features. Optimizing...")

    optimized_features = []
    
    for i, feature in enumerate(features):
        props = feature.get('properties', {})
        geometry = feature.get('geometry', {})
        
        # Keep only essential properties
        new_props = {
            'idsls': props.get('idsls', ''),
            'nmsls': props.get('nmsls', ''),
            'nmdesa': props.get('nmdesa', ''),
            'nmkec': props.get('nmkec', ''),
            'kode_pos': props.get('kode_pos', '')
        }
        
        # Round coordinates to 6 decimal places to save space
        if geometry and 'coordinates' in geometry:
            def round_coords(coords):
                if isinstance(coords, (float, int)):
                    return round(coords, 6)
                elif isinstance(coords, list):
                    return [round_coords(c) for c in coords]
                return coords
            
            # Create a new geometry object to avoid modifying the original in place if that matters
            # (though here we are just reading)
            new_geometry = {
                'type': geometry.get('type'),
                'coordinates': round_coords(geometry.get('coordinates'))
            }
        else:
            new_geometry = geometry

        optimized_features.append({
            'type': 'Feature',
            'properties': new_props,
            'geometry': new_geometry
        })

    optimized_data = {
        'type': 'FeatureCollection',
        'features': optimized_features
    }

    print(f"Writing optimized data to {output_path}...")
    try:
        with open(output_path, 'w', encoding='utf-8') as f:
            # separators=(',', ':') removes whitespace around separators
            json.dump(optimized_data, f, separators=(',', ':'))
        
        original_size = os.path.getsize(input_path)
        new_size = os.path.getsize(output_path)
        print(f"Done! Original size: {original_size/1024:.2f} KB, Optimized size: {new_size/1024:.2f} KB")
        print(f"Reduction: {(1 - new_size/original_size)*100:.2f}%")
        
    except Exception as e:
        print(f"Error writing output file: {e}")

if __name__ == "__main__":
    input_file = '/Users/nasrul/flutter/direktori/assets/geojson/final_sls.geojson'
    output_file = '/Users/nasrul/flutter/direktori/assets/geojson/final_sls_optimized.json'
    optimize_geojson(input_file, output_file)
