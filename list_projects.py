import sys
from roboflow import Roboflow

def main():
    try:
        rf = Roboflow(api_key="3uN5WMO5l41xX606zNXq")
        workspace = rf.workspace("curtis-papa-ankomah-poku")
        print("Projects in workspace:")
        for project_name in workspace.projects():
            print(project_name)
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
