# Android Emulator Setup and Usage on Linux

## Running the Android Emulator

To start the Android emulator on Linux, use the following command:

```bash
emulator -avd Pixel_9_Pro
```

### Command Breakdown

- `emulator` - The Android emulator executable from the Android SDK
- `-avd Pixel_9_Pro` - Specifies the Android Virtual Device (AVD) name to launch
- `&` - Runs the emulator in the background, allowing you to continue using the terminal

## How to Use the Emulator in Linux with Android Studio

### Prerequisites

1. **Android Studio installed** - Download from [developer.android.com](https://developer.android.com)
2. **Android SDK** - Included with Android Studio
3. **Emulator and platform tools** - Install via SDK Manager in Android Studio

### Steps to Launch the Emulator

1. **Create or select an AVD**
   - Open Android Studio
   - Go to Tools > Device Manager
   - Create a new virtual device or select an existing one (e.g., Pixel_9_Pro)

2. **Using Android Studio GUI**
   - In Device Manager, click the play icon next to your AVD to launch it

3. **Using Terminal (Linux)**
   - Open a terminal
   - Navigate to your Android SDK emulator directory: `~/Android/Sdk/emulator/`
   - Run the command:
     ```bash
     ./emulator -avd Pixel_9_Pro &
     ```
   - The emulator will boot in the background

4. **Verify the Emulator is Running**
   - Run: `adb devices`
   - Your emulator should appear in the list as `emulator-5554`

5. **Connect with Android Studio**
   - Once running, Android Studio will automatically detect the emulator
   - Deploy your app by clicking the Run button

### Tips

- **Speed up startup:** Add `-no-boot-anim` flag to skip the boot animation
- **Allocate resources:** Use `-cores 4` to specify CPU cores
- **Snapshot management:** Use `-snapshot default` to load a saved state quickly
- **Close the emulator:** Use `adb emu kill` or close the window normally
