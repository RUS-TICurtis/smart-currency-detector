# Smart Currency Denomination Detection System

## Flutter-Only Technology Stack (MVP)

---

# 1. Project Overview
The Smart Currency Denomination Detection System is an offline, cross-platform assistive application built entirely within the Flutter ecosystem. It is designed to help users, particularly individuals with visual impairments, identify Ghanaian currency denominations through real-time camera scanning or captured images.

# 2. System Architecture
```text
                   Flutter Application
          (Android • iOS • Web • Desktop)
                  │
      ┌───────────┼───────────┐
      │           │           │
 Camera Module  AI Inference Accessibility
      │           │           │
 (camera pkg) (tflite_flutter) (flutter_tts)
      │           │           │
      └───────────┼───────────┘
                  │
          Local Device Storage
            (Hive / Isar)
```

# 3. Core Framework & UI
| Technology | Purpose |
| :--- | :--- |
| **Flutter** | Cross-platform application framework |
| **Dart** | Core programming language |
| **Material 3** | User Interface design system |
| **flutter_riverpod** | State management and dependency injection |
| **go_router** | Declarative routing and navigation |
| **flutter_hooks** | Managing widget lifecycle (animations, controllers) |

# 4. Hardware Integrations (Flutter Packages)
| Package | Purpose |
| :--- | :--- |
| **camera** | Accessing the device's physical camera for real-time feeds |
| **image_picker** | Alternative method to select images from the gallery |
| **permission_handler** | Requesting camera and storage permissions safely |

# 5. AI & Image Processing (Dart/Flutter Native)
*Note: Model training is assumed to be done externally (e.g., Google Colab/Kaggle), but the entire operational stack is Flutter.*

| Package | Purpose |
| :--- | :--- |
| **tflite_flutter** | Running the pre-trained TensorFlow Lite model entirely on-device |
| **image** | Dart-native image manipulation (resizing, cropping, formatting for the AI model) |

# 6. Accessibility & Speech
| Package | Purpose |
| :--- | :--- |
| **flutter_tts** | Offline Text-to-Speech to announce detected denominations |
| **Semantics (Built-in)** | Flutter's native semantic trees for screen reader support |

# 7. Local Storage
| Package | Purpose |
| :--- | :--- |
| **hive / hive_flutter** | Fast, lightweight NoSQL storage for saving user settings (e.g., speech rate, volume) |
| **path_provider** | Finding the correct local directories on iOS/Android to store the Hive database |

# 8. Development & Testing
| Tool | Purpose |
| :--- | :--- |
| **flutter_test** | Unit and widget testing |
| **integration_test** | End-to-end testing on real devices |
| **flutter analyze** | Static code analysis and linting |

---

# 9. Why a Flutter-Only Stack?
By relying exclusively on Flutter and Dart for the production application, we achieve:
1. **Single Codebase**: Maintain only one project for Android, iOS, and Web.
2. **Offline-First**: Everything from image capturing to AI inference (`tflite_flutter`) to speech generation (`flutter_tts`) runs locally on the device without needing a backend server.
3. **High Performance**: Native compilation ensures the real-time camera feed and AI model run smoothly.
4. **Accessible by Design**: Flutter's native accessibility features combined with local TTS makes it highly optimized for visually impaired users.
