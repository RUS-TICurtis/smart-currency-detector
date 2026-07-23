# YOLOv11 Object Detection Training Script — ONNX Export
# Replaces TFLite export (which had INT8 calibration crashes) with ONNX Runtime.
#
# INSTRUCTIONS (Google Colab):
# 1. Open Google Colab (colab.research.google.com) and create a New Notebook.
# 2. Go to Runtime -> Change runtime type -> Hardware accelerator -> T4 GPU.
# 3. Upload your Roboflow YOLOv11 dataset zip file to the Colab files pane.
# 4. Unzip the dataset by running this command in a cell:
#    !unzip -q "/content/drive/MyDrive/Colab Notebooks/GhanaCediDetection.yolov11.zip" -d /content/dataset
# 5. Install dependencies by running in a cell:
#    !pip install ultralytics onnx onnxruntime onnxslim
# 6. Copy and paste the code below into a new cell and run it!
#
# OUTPUT:
# - currency_detector/model_run/weights/best_fp32.onnx  (full precision - reference)
# - currency_detector/model_run/weights/best_fp16.onnx  (half precision - recommended for mobile)

import os
import yaml
import shutil


def fix_yaml_paths(yaml_path: str) -> None:
    """
    Roboflow zip files often have relative paths that break in Colab.
    This fixes them to absolute paths so Ultralytics can find the images.
    """
    print("Checking data.yaml paths...")
    if not os.path.exists(yaml_path):
        print(f"Error: Could not find {yaml_path}")
        return

    with open(yaml_path, "r") as f:
        data = yaml.safe_load(f)

    base_dir = os.path.abspath(os.path.dirname(yaml_path))

    for key in ["train", "val", "test"]:
        if key in data and isinstance(data[key], str):
            if data[key].startswith("../"):
                data[key] = os.path.join(base_dir, data[key].replace("../", ""))
            elif not data[key].startswith("/"):
                data[key] = os.path.join(base_dir, data[key])

    with open(yaml_path, "w") as f:
        yaml.dump(data, f, default_flow_style=False)

    print("Fixed data.yaml paths!\n")


def train(yaml_file: str):
    """Trains YOLOv11-Nano on the Ghana Cedi dataset and returns the trained model."""
    from ultralytics import YOLO

    print("Loading YOLOv11 Nano model (pre-trained on COCO)...")
    model = YOLO("yolo11n.pt")

    print("Starting training...\n")
    model.train(
        data=yaml_file,
        epochs=50,
        imgsz=640,
        batch=16,
        project="currency_detector",
        name="model_run",
        # Optimizer — AdamW converges more stably than SGD on small datasets
        optimizer="AdamW",
        lr0=0.001,
        weight_decay=0.0005,
        # Augmentation — helps generalise across lighting conditions and angles
        hsv_h=0.015,   # Hue shift (simulates different lighting colours)
        hsv_s=0.7,     # Saturation shift
        hsv_v=0.4,     # Brightness/value shift
        fliplr=0.5,    # Horizontal flip (banknotes can be held either way)
        mosaic=1.0,    # Mosaic augmentation (combines 4 images per sample)
        # Checkpointing
        save=True,
        save_period=10,
    )

    return model


def export_onnx(model, weights_dir: str) -> None:
    """
    Exports the best checkpoint to ONNX format (FP32 and FP16).

    Why ONNX instead of TFLite?
    - No INT8 calibration crashes (the bug in 3_yolo_training.py is gone).
    - Direct PyTorch -> ONNX conversion with no lossy intermediate format.
    - FP16 halves the model size with zero accuracy loss.
    - flutter_onnxruntime uses CoreML (iOS) and NNAPI (Android) automatically
      for hardware-accelerated inference.
    """
    best_pt = os.path.join(weights_dir, "best.pt")

    # ------------------------------------------------------------------ #
    #  Export 1: FP32  (reference — use for accuracy benchmarking only)  #
    # ------------------------------------------------------------------ #
    print("\n[1/2] Exporting FP32 ONNX model...")
    model.export(
        format="onnx",
        imgsz=640,
        simplify=True,   # Runs onnxslim to remove redundant graph nodes
        opset=17,        # Opset 17 has wide ONNX Runtime mobile support
        dynamic=False,   # Fixed batch size = 1 for mobile inference
    )
    fp32_src = best_pt.replace(".pt", ".onnx")
    fp32_dst = os.path.join(weights_dir, "best_fp32.onnx")
    if os.path.exists(fp32_src):
        shutil.move(fp32_src, fp32_dst)
        print(f"  Saved: {fp32_dst}")

    # ------------------------------------------------------------------ #
    #  Export 2: FP16  (recommended for mobile)                          #
    #  Half the file size, same accuracy, hardware-accelerated on        #
    #  modern Android (NNAPI) and iOS (CoreML) chips.                    #
    #  Avoids INT8 calibration entirely — no more crashes!               #
    # ------------------------------------------------------------------ #
    print("\n[2/2] Exporting FP16 ONNX model (recommended for Flutter)...")
    model.export(
        format="onnx",
        imgsz=640,
        simplify=True,
        opset=17,
        dynamic=False,
        half=True,       # FP16 — avoids INT8 calibration problems entirely
    )
    fp16_src = best_pt.replace(".pt", ".onnx")
    fp16_dst = os.path.join(weights_dir, "best_fp16.onnx")
    if os.path.exists(fp16_src):
        shutil.move(fp16_src, fp16_dst)
        print(f"  Saved: {fp16_dst}")


def validate_onnx(weights_dir: str) -> None:
    """
    Quick sanity check — loads both exported ONNX models and verifies the
    graph is structurally valid. Catches corrupt exports before you download.
    """
    import onnx

    print("\n--- ONNX Model Validation ---")
    for fname in ["best_fp32.onnx", "best_fp16.onnx"]:
        fpath = os.path.join(weights_dir, fname)
        if not os.path.exists(fpath):
            print(f"  SKIP  {fname}  (not found)")
            continue
        try:
            loaded = onnx.load(fpath)
            onnx.checker.check_model(loaded)
            size_mb = os.path.getsize(fpath) / (1024 * 1024)
            print(f"  PASS  {fname}  ({size_mb:.1f} MB)")
        except Exception as e:
            print(f"  FAIL  {fname}: {e}")


def main() -> None:
    yaml_file = "dataset/data.yaml"
    weights_dir = "currency_detector/model_run/weights"

    # Step 1 – Fix Roboflow relative paths
    fix_yaml_paths(yaml_file)

    # Step 2 – Train the YOLOv11 Nano model
    model = train(yaml_file)

    # Step 3 – Export to ONNX (FP32 reference + FP16 mobile)
    export_onnx(model, weights_dir)

    # Step 4 – Validate the exported files are not corrupt
    validate_onnx(weights_dir)

    print("\n" + "=" * 60)
    print("DONE!")
    print("=" * 60)
    print(f"  FP32 model : {weights_dir}/best_fp32.onnx  (accuracy reference)")
    print(f"  FP16 model : {weights_dir}/best_fp16.onnx  <-- copy this to Flutter")
    print()
    print("Flutter integration:")
    print("  1. pubspec.yaml dep:  flutter_onnxruntime: ^1.8.3")
    print("  2. Copy best_fp16.onnx to: mobile/assets/models/currency_detector.onnx")
    print("  3. Register the asset in pubspec.yaml under flutter -> assets")
    print("=" * 60)


if __name__ == "__main__":
    main()
