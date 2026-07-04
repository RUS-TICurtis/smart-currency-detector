import os
import tensorflow as tf
from tensorflow.keras.preprocessing.image import ImageDataGenerator
import matplotlib.pyplot as plt

# Configuration
DATASET_DIR = '../dataset'
BATCH_SIZE = 32
IMAGE_SIZE = (224, 224)

def setup_data_generators():
    print(f"Looking for dataset in: {os.path.abspath(DATASET_DIR)}")
    
    if not os.path.exists(DATASET_DIR) or len(os.listdir(DATASET_DIR)) == 0:
        raise ValueError(f"Dataset directory '{DATASET_DIR}' is empty or does not exist. Please add images of currency notes categorized by folders (e.g., dataset/10_cedis, dataset/20_cedis).")

    # We use ImageDataGenerator for real-time data augmentation
    # This helps the model generalize better to different lighting/angles
    datagen = ImageDataGenerator(
        rescale=1./255,           # Normalize pixel values
        rotation_range=20,        # Randomly rotate images up to 20 degrees
        width_shift_range=0.2,    # Randomly translate images horizontally
        height_shift_range=0.2,   # Randomly translate images vertically
        shear_range=0.15,         # Randomly shear images
        zoom_range=0.2,           # Randomly zoom into images
        horizontal_flip=True,     # Randomly flip images horizontally
        brightness_range=[0.8, 1.2], # Randomly adjust brightness
        validation_split=0.2      # 20% of data for validation
    )

    print("Setting up Training Generator...")
    train_generator = datagen.flow_from_directory(
        DATASET_DIR,
        target_size=IMAGE_SIZE,
        batch_size=BATCH_SIZE,
        class_mode='categorical',
        subset='training'
    )

    print("Setting up Validation Generator...")
    val_generator = datagen.flow_from_directory(
        DATASET_DIR,
        target_size=IMAGE_SIZE,
        batch_size=BATCH_SIZE,
        class_mode='categorical',
        subset='validation'
    )

    return train_generator, val_generator

def visualize_augmented_images(train_generator):
    # Fetch a batch of augmented images
    images, labels = next(train_generator)
    
    class_indices = train_generator.class_indices
    labels_map = {v: k for k, v in class_indices.items()}
    
    plt.figure(figsize=(10, 10))
    for i in range(min(9, len(images))):
        plt.subplot(3, 3, i + 1)
        plt.imshow(images[i])
        # Find the class index (where label is 1)
        class_idx = labels[i].argmax()
        plt.title(labels_map[class_idx])
        plt.axis('off')
    plt.tight_layout()
    plt.show()

if __name__ == "__main__":
    try:
        train_gen, val_gen = setup_data_generators()
        print("\nClasses found:", train_gen.class_indices)
        visualize_augmented_images(train_gen)
    except Exception as e:
        print(f"Error: {e}")
