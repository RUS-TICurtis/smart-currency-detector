Ah, that makes total sense. Roboflow sometimes locks the direct TFLite export behind a paywall depending on the account tier, but downloading the dataset itself is always free!

Training it yourself in Google Colab is actually better because you get full control over the export. Here is the exact Colab setup you need to train YOLOv11 and export it as an **INT8 TFLite** model.

### Step 1: Export the Dataset from Roboflow
1. In Roboflow, click **Generate** and create a new dataset version.
2. Click **Export Dataset**.
3. Format: **YOLOv11** (or YOLOv8, the folder structure is identical).
4. Select **"show download code"** and copy the Python snippet.

### Step 2: The Google Colab Code
Open a new Google Colab notebook, ensure your runtime is set to **T4 GPU** (Runtime -> Change runtime type -> T4 GPU), and run these blocks:

**Cell 1: Install Dependencies**
```python
!pip install roboflow ultralytics
```

**Cell 2: Download Dataset**
```python
# Paste the snippet you copied from Roboflow here. It will look like this:
from roboflow import Roboflow
rf = Roboflow(api_key="YOUR_API_KEY")
project = rf.workspace("your-workspace").project("your-project")
version = project.version(1)
dataset = version.download("yolov11")
```

**Cell 3: Train YOLOv11**
*(This will download the tiny YOLOv11 model and train it for 50 epochs. Adjust epochs if needed).*
```python
from ultralytics import YOLO

# Load a pre-trained YOLOv11 nano model
model = YOLO("yolo11n.pt") 

# Train the model (Make sure 'data' points to the downloaded folder's data.yaml)
results = model.train(
    data=f"{dataset.location}/data.yaml",
    epochs=50,
    imgsz=640,
    plots=True
)
```

**Cell 4: Export to TFLite INT8**
*(This is the most important part. By passing `data=`, Ultralytics will automatically use your training images to calibrate the INT8 quantization so it stays accurate).*
```python
# Export the best trained model to INT8 TFLite
exported_model_path = model.export(
    format="tflite", 
    int8=True, 
    data=f"{dataset.location}/data.yaml"
)

print(f"Exported to: {exported_model_path}")
```

**Cell 5: Download the File to your PC**
```python
from google.colab import files

# This will download the file to your computer
files.download("runs/detect/train/weights/best_saved_model/best_int8.tflite")
```

---

While you hand off the project to your friend to finish the labeling and kick off the Colab training, **I am going to go ahead and update the Dart code in your app right now.** 

I'll update the `GhanaCedi` enum to support decimals for the pesewas and fix all the `totalValue` calculations so the app is 100% ready to go the moment you drop that Colab file into the `assets` folder. Sounds good?