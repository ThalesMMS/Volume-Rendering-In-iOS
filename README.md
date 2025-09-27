# Volume-Rendering-In-iOS
[](https://github.com/eunwonki/Volume-Rendering-In-iOS#volume-rendering-in-ios)
Implement volume-rendering for patient-data on iOS.
Direct volume rendering, projection modes, and multi-planar reconstruction on iOS using SceneKit + Metal.

This fork extends the original sample with enhanced projection pipelines, tri-planar multi-planar reconstruction (MPR), and optional DICOM loading through GDCM.

### Tech
[](https://github.com/eunwonki/Volume-Rendering-In-iOS#tech)
* Metal Shader (Graphic)
* SceneKit (Scene Graph)
* Metal fragment ray-marching for DVR/MIP/MinIP/AIP
* Optional GDCM bridge for native DICOM series loading
* Snapshot helpers for debugging transfer functions and volume slices

### Source Project
[](https://github.com/eunwonki/Volume-Rendering-In-iOS#source-project)
[Unity Volume Rendering](https://github.com/mlavik1/UnityVolumeRendering)

### Data
- Sample volumes are included in the app bundle under `VolumeRendering-iOS/Resource/Images/`
  - `chest.raw.zip` (Int16 signed LE)
  - `head.raw.zip` (Int16 signed LE)
- Transfer Functions (TF) in `VolumeRendering-iOS/Resource/TransferFunction/`
  - `ct_arteries.tf`, `ct_entire.tf`, `ct_lung.tf`
- DICOM: when GDCM libraries are linked (see below), `.dcm` series and zipped folders can be imported at runtime

### Features
- Rendering Modes: Direct Volume Rendering (DVR), Surface, Maximum Intensity Projection (MIP), Minimum Intensity Projection (MinIP), Average Intensity Projection (AIP)
- Projection Enhancements: optional transfer function application, HU windowing, and min/max/mean slab thickness controls
- Tri-planar MPR: simultaneous axial/coronal/sagittal reconstructions with draggable crosshairs, slab thickness control, oblique rotation, and shared 1D transfer function
- Transfer Function 1D: shared between DVR and MPR with presets for common CT windows
- Empty-space skipping (conservative) for DVR performance
- Snapshot helpers for exporting volume slices and transfer function textures during development

### Contributors
- Thales Matheus Mendonça Santos — refined MinIP, AIP, and DVR pipelines, and implemented the tri-planar MPR workflow with optional GDCM-based DICOM integration.

## How To Run in your Local
[](https://github.com/eunwonki/Volume-Rendering-In-iOS#how-to-run-in-your-local)

### At First,
[](https://github.com/eunwonki/Volume-Rendering-In-iOS#at-first)
You should set git-lfs setting.  
Because raw data file is so bigger than supported in git.

install git-lfs first,

```bash
brew install git-lfs
```

and set git lfs on in your local

```bash
git-lfs install
```

and pull lfs from server

```bash
git lfs pull
```

### Run from Xcode
1. Open the Xcode project `VolumeRendering-iOS.xcodeproj`.
2. Select a device (prefer iPhone 15 Pro Max) and run.

### DICOM via GDCM
1. Build GDCM for iOS (static libs or an XCFramework). A simple path is to use CMake with the iOS toolchain or to reuse prebuilt binaries from your toolchain.
2. Copy the resulting headers and libraries into `Vendor/GDCM/include` and `Vendor/GDCM/lib` respectively. The Xcode target already adds these locations to the header and library search paths.
3. Add the required static libraries (for example `libgdcmCommon`, `libgdcmMSFF`, `libexpat`, `libz`, `libopenjp2`, `libcharls`) to **Link Binary With Libraries**. If you use an `.xcframework`, drop it in the folder and drag it into Xcode.
4. Run the app, tap **Import DICOM**, and select a `.zip`, folder, or file representing a series. When GDCM is not linked, the importer gracefully reports that the native loader is unavailable.

### Screenshots

|Surface Rendering|Direct Volume Rendering|Maximum Intensity Projection|
|-|-|-|
|![](Screenshot/6.jpg)|![](Screenshot/10.jpeg)|![](Screenshot/7.jpeg)|

surface rendring

direct volume rendering

maximum intensity projection

[![](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/raw/main/Screenshot/6.jpg?raw=true)](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/blob/main/Screenshot/6.jpg?raw=true)

[![](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/raw/main/Screenshot/10.jpeg?raw=true)](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/blob/main/Screenshot/10.jpeg?raw=true)

[![](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/raw/main/Screenshot/7.jpeg?raw=true)](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/blob/main/Screenshot/7.jpeg?raw=true)

#### Direct Volume Rendering
[](https://github.com/eunwonki/Volume-Rendering-In-iOS#direct-volume-rendering)

|CT-Coronary-Arteries|CT-Chest-Entire|CT-Lung|
|-|-|-|
|![](Screenshot/9.jpeg)|![](Screenshot/10.jpeg)|![](Screenshot/12.jpg)|

CT-Coronary-Arteries

CT-Chest-Entire

CT-Lung

[![](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/raw/main/Screenshot/9.jpeg?raw=true)](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/blob/main/Screenshot/9.jpeg?raw=true)

[![](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/raw/main/Screenshot/10.jpeg?raw=true)](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/blob/main/Screenshot/10.jpeg?raw=true)

[![](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/raw/main/Screenshot/12.jpg?raw=true)](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/blob/main/Screenshot/12.jpg?raw=true)

#### Lighting
[](https://github.com/eunwonki/Volume-Rendering-In-iOS#lighting)

|Lighting Off|Lighting On|
|-|-|
|![](Screenshot/9.jpeg)|![](Screenshot/8.jpeg)|

Lighting Off

Lighting On

[![](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/raw/main/Screenshot/9.jpeg?raw=true)](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/blob/main/Screenshot/9.jpeg?raw=true)

[![](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/raw/main/Screenshot/8.jpeg?raw=true)](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/blob/main/Screenshot/8.jpeg?raw=true)

[![](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/raw/main/Screenshot/10.jpeg?raw=true)](https://github.com/eunwonki/Metal-Based-Volume-Rendering-In-iOS/blob/main/Screenshot/10.jpeg?raw=true)

### Licenses
- This project is based on `Unity Volume Rendering` (`mlavik1/UnityVolumeRendering`). See upstream for original license.
- All new code in this repository is released under the Apache License 2.0 (`LICENSE`).

### Known issues
- Performance metrics depend on device; baseline validation targets iPhone 15 Pro Max.
- Some presets may require TF shift adjustments for best visual results.
- Large RAW datasets require Git LFS; ensure `git lfs pull` completed successfully.
