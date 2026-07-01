# YOLOv11 Object Detection Training Script for Google Colab
# 
# INSTRUCTIONS:
# 1. Open Google Colab (colab.research.google.com) and create a New Notebook.
# 2. Go to Runtime -> Change runtime type -> Hardware accelerator -> T4 GPU.
# 3. Upload your Roboflow YOLOv11 dataset zip file to the Colab files pane.
# 4. Unzip the dataset by running this command in a cell:
#    !unzip -q your_dataset.zip -d dataset/
# 5. Install the ultralytics package by running:
#    !pip install ultralytics
# 6. Copy and paste the code below into a new cell and run it!

import os
import yaml
from ultralytics import YOLO

def fix_yaml_paths(yaml_path):
    """Roboflow zip files often have relative paths that break in Colab. This fixes them."""
    print("Checking data.yaml paths...")
    if not os.path.exists(yaml_path):
        print(f"Error: Could not find {yaml_path}")
        return

    with open(yaml_path, 'r') as file:
        data = yaml.safe_load(file)

    # Convert relative paths to absolute paths based on the yaml file's location
    base_dir = os.path.abspath(os.path.dirname(yaml_path))
    
    for key in ['train', 'val', 'test']:
        if key in data and isinstance(data[key], str):
            # If it's a relative path like '../train/images', fix it
            if data[key].startswith('../'):
                data[key] = os.path.join(base_dir, data[key].replace('../', ''))
            elif not data[key].startswith('/'):
                data[key] = os.path.join(base_dir, data[key])

    with open(yaml_path, 'w') as file:
        yaml.dump(data, file, default_flow_style=False)
    print("Fixed data.yaml paths for Google Colab!")

def main():
    yaml_file = "dataset/data.yaml"
    
    # 1. Fix the paths in the YAML file so Ultralytics can find your images
    fix_yaml_paths(yaml_file)

    print("\nLoading YOLOv11 Nano model...")
    # Load a pretrained YOLOv11 Nano model
    model = YOLO("yolo11n.pt") 

    print("\nStarting training...")
    # Train the model
    model.train(
        data=yaml_file, 
        epochs=50,                
        imgsz=640,                
        batch=16,
        project="currency_detector",
        name="model_run"
    )

    print("\nTraining complete! Exporting to TensorFlow Lite...")
    # Export the trained model to TFLite format
    # We remove int8=True because it can cause calibration crashes on some datasets
    model.export(format="tflite") 
    
    print("\nExport complete! Look in the 'currency_detector/model_run/weights' folder for your .tflite file!")

if __name__ == "__main__":
    main()
