# Volume-Rendering-In-iOS
Direct volume rendering, projection modes, and multi-planar reconstruction on iOS using SceneKit + Metal.

### Tech
- Metal (fragment ray-marching for DVR/MIP/MinIP/AIP)
- SceneKit (scene graph and material hosting)
- Optional GDCM bridge for native DICOM series loading

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

### How to run locally
1. Install Git LFS and fetch large files:
   ```bash
   brew install git-lfs
   git lfs install
   git lfs pull
   ```
2. Open the Xcode project `VolumeRendering-iOS.xcodeproj`.
3. Select a device (prefer iPhone 15 Pro Max) and run.

### DICOM via GDCM
1. Build GDCM for iOS (static libs or an XCFramework). A simple path is to use CMake with the iOS toolchain or to reuse prebuilt binaries from your toolchain.
2. Copy the resulting headers and libraries into `Vendor/GDCM/include` and `Vendor/GDCM/lib` respectively. The Xcode target already adds these locations to the header and library search paths.
3. Add the required static libraries (for example `libgdcmCommon`, `libgdcmMSFF`, `libexpat`, `libz`, `libopenjp2`, `libcharls`) to **Link Binary With Libraries**. If you use an `.xcframework`, drop it in the folder and drag it into Xcode.
4. Run the app, tap **Import DICOM**, and select a `.zip`, folder, or file representing a series. When GDCM is not linked, the importer gracefully reports that the native loader is unavailable.

### Screenshots

|Surface Rendering|Direct Volume Rendering|Maximum Intensity Projection|
|-|-|-|
|![](Screenshot/6.jpg)|![](Screenshot/10.jpeg)|![](Screenshot/7.jpeg)|

#### Direct Volume Rendering
|CT-Coronary-Arteries|CT-Chest-Entire|CT-Lung|
|-|-|-|
|![](Screenshot/9.jpeg)|![](Screenshot/10.jpeg)|![](Screenshot/12.jpg)|

#### Lighting
|Lighting Off|Lighting On|
|-|-|
|![](Screenshot/9.jpeg)|![](Screenshot/8.jpeg)|

### Licenses
- This project is based on `Unity Volume Rendering` (`mlavik1/UnityVolumeRendering`). See upstream for original license.
- All new code in this repository is released under the Apache License 2.0 (`LICENSE`).

### Known issues
- Performance metrics depend on device; baseline validation targets iPhone 15 Pro Max.
- Some presets may require TF shift adjustments for best visual results.
- Large RAW datasets require Git LFS; ensure `git lfs pull` completed successfully.
