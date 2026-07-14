import sys
from roboflow import Roboflow

def main():
    try:
        rf = Roboflow(api_key="3uN5WMO5l41xX606zNXq")
        workspace = rf.workspace("curtis-papa-ankomah-poku")
        project = workspace.project("ghana-currency-dataset")
        print("Uploading dataset...")
        project.upload("C:\\Users\\Curtis\\Downloads\\Ghana-Cedis-Currency")
        print("Upload completed successfully!")
    except Exception as e:
        print(f"Error during upload: {e}")

if __name__ == "__main__":
    main()
