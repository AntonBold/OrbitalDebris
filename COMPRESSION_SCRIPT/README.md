# Video Compression to 1-Bit Per Pixel

This Python script compresses grayscale video data into a 1-bit-per-pixel format (`.y` files). It processes raw grayscale videos frame by frame, thresholding pixel values to either 0 or 1.

---

## Getting Started

### 1. Install FFmpeg
FFmpeg is required to convert standard video files (e.g., `.mp4`) into raw grayscale `.y` files that this script can process.  

- **macOS (Homebrew):**
```bash 
brew install ffmpeg
```

- **Windows:**
Download the executable from the FFmpeg official site and add it to your PATH.  

### 2. Convert a Video to Raw Grayscale .y File
Use the following FFmpeg command to convert your video into the raw 8-bit grayscale format:

```bash
ffmpeg -i /path/to/your/input_video.mp4 \
    -vf format=gray \
    -pix_fmt gray \
    -f rawvideo \
    /path/to/your/output_video.y
```
Replace `/path/to/your/input_video.mp4` with your original video file path.  
Replace `/path/to/your/output_video.y` with the desired output path for the raw video file.  
This `.y` file is what you will feed into the Python compression script.  

### 3. Run the Compression Script

Place your `.y` file in an accessible location.

Run the script:
```bash
python compress_video.py
```

Follow the prompts:

Provide the filepath of the `.y` video to compress.
Provide the output filepath and name for the compressed file.
Specify the number of frames you wish to convert.
The script will process each frame, threshold the pixels, and produce a compressed 1-bit-per-pixel output file.

### 4. Example Usage

Suppose you have:
Input video:`~/Videos/sample.mp4`  
Output raw video: `~/Videos/sample_raw.y`  
Output compressed video: `~/Videos/sample_compressed`  
Steps:
#### Convert video to raw grayscale
```bash
ffmpeg -i ~/Videos/sample.mp4 -vf format=gray -pix_fmt gray -f rawvideo ~/Videos/sample_raw.y 
```

#### Run the Python script
``` bash
python compress_video.py
```
**Provide `~/Videos/sample_raw.y` as input**  
**Provide `~/Videos/sample_compressed` as output**   
**Specify the number of frames to process**  

### 5. Notes
Ensure the input .y file resolution matches the script's width and height parameters (default: 1920x1080).
The script includes basic error handling for missing files, permissions, or directory issues.
**GITHUB WILL NOT TRACK FILES LARGER THAN 100MB** -- Raw .y from ffmpeg conversion will need to be stored only locally. Likewise, compressed files larger than 100mb will need to be stored locally.

**Author**
Adam Welsh
