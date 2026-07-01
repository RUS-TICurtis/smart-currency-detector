import os
import tensorflow as tf
from tensorflow.keras.applications import MobileNetV2
from tensorflow.keras.layers import Dense, GlobalAveragePooling2D, Dropout
from tensorflow.keras.models import Model
from tensorflow.keras.optimizers import Adam
from tensorflow.keras.callbacks import ModelCheckpoint, EarlyStopping

# We import the data generator from our previous script
from 1_data_preprocessing import setup_data_generators, IMAGE_SIZE

def build_model(num_classes):
    # Load MobileNetV2 pre-trained on ImageNet without the top classification layer
    base_model = MobileNetV2(
        input_shape=(*IMAGE_SIZE, 3),
        include_top=False,
        weights='imagenet'
    )
    
    # Freeze the base model layers so we don't destroy the pre-trained features
    base_model.trainable = False

    # Add custom classification head
    x = base_model.output
    x = GlobalAveragePooling2D()(x)
    x = Dense(128, activation='relu')(x)
    x = Dropout(0.5)(x) # Prevent overfitting
    predictions = Dense(num_classes, activation='softmax')(x)

    model = Model(inputs=base_model.input, outputs=predictions)
    
    model.compile(
        optimizer=Adam(learning_rate=0.001),
        loss='categorical_crossentropy',
        metrics=['accuracy']
    )
    return model

def convert_to_tflite(keras_model_path, tflite_model_path):
    print("Converting model to TensorFlow Lite format...")
    model = tf.keras.models.load_model(keras_model_path)
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    
    # Optional: Apply quantization to reduce model size further
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    
    tflite_model = converter.convert()
    
    with open(tflite_model_path, 'wb') as f:
        f.write(tflite_model)
    print(f"TFLite model saved to {tflite_model_path}")

if __name__ == "__main__":
    train_gen, val_gen = setup_data_generators()
    num_classes = len(train_gen.class_indices)
    
    print(f"\nBuilding model for {num_classes} classes...")
    model = build_model(num_classes)
    
    # Callbacks
    checkpoint_path = "best_model.h5"
    checkpoint = ModelCheckpoint(checkpoint_path, monitor='val_accuracy', save_best_only=True, mode='max', verbose=1)
    early_stop = EarlyStopping(monitor='val_loss', patience=5, restore_best_weights=True)
    
    print("\nStarting training...")
    EPOCHS = 20
    history = model.fit(
        train_gen,
        epochs=EPOCHS,
        validation_data=val_gen,
        callbacks=[checkpoint, early_stop]
    )
    
    # Convert best model to TFLite
    convert_to_tflite(checkpoint_path, "currency_detector.tflite")
    print("\nTraining and Conversion Complete! You can now move currency_detector.tflite to your Flutter assets.")
