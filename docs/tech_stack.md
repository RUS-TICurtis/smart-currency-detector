# Smart Currency Denomination Detection System
## Technology Stack Document (MVP v1.0)

*(This document contains the MVP v1.0 architecture specifications)*

## 1. Project Overview
The Smart Currency Denomination Detection System is an AI-powered, cross-platform assistive application designed to help users, particularly individuals with visual impairments, identify Ghanaian currency denominations through real-time camera scanning or captured images. The application operates entirely offline and provides spoken feedback after successful recognition.

## 2. System Architecture
- Flutter Application (Android • iOS • Web)
- Camera Module
- AI Engine (TensorFlow Lite)
- Accessibility Module
- Local Device Storage

## 3. Frontend
- Flutter / Dart
- Material Design 3
- Riverpod (State management)
- GoRouter (Navigation)
- Flutter Hooks (Optional)

## 4. Artificial Intelligence Stack
- Python
- TensorFlow / TensorFlow Lite
- OpenCV
- NumPy, Pandas, Matplotlib

## 5. AI Model
Recommended model: TensorFlow Lite CNN.
Future upgrades: MobileNetV3, EfficientNet Lite, YOLOv8 Nano.

## 6. Image Processing
- OpenCV
- Image package (Flutter)
Preprocessing includes Resize, Crop, Brightness normalization, Rotation correction, Noise reduction.

## 7. Camera
- `camera` package
- `image_picker`
- `permission_handler`

## 8. Offline Speech
- `flutter_tts`

## 9. Local Storage
- Hive / Isar

## 10. Database & Backend (Future)
- FastAPI, PostgreSQL, Supabase
