import numpy as np
from bitstring import BitArray


def compress_to_1bpp(
    input_path,
    output_path,
    width,
    height,
    num_frames_process,
    threshold=128,
):
    print("Beginning compression...\n")
    pixels_per_frame = width * height
    bytes_per_frame = pixels_per_frame  # because input is 8-bit gray

    try:
        with open(input_path, "rb") as f_in, open(output_path, "wb") as f_out:

            frame_index = 0
            bit_array = BitArray('')

            while frame_index < num_frames_process:
                # Read one full frame
                frame_bytes = f_in.read(bytes_per_frame)
                if len(frame_bytes) < bytes_per_frame:
                    break  # end of file

                # Convert to NumPy array for vector operations
                frame = np.frombuffer(frame_bytes, dtype=np.uint8)

                # Threshold to 0 or 1
                binary = (frame >= threshold).astype(np.uint8)

                for byteNum in range(bytes_per_frame):
                    if binary[byteNum] == 0x01:
                        bit_array.append('0b1')
                    else:
                        bit_array.append('0b0')

                frame_index += 1

            f_out.write(bit_array.bytes)

        print(f"Done. Converted {frame_index} frame(s).\n")
    except FileNotFoundError:
        print("ERROR: file not found\n")
    except PermissionError:
        print("ERROR: file exists, but you do not have read permissions\n")
    except IsADirectoryError:
        print("ERROR: tried to open a directory instead of a file\n")
    except NotADirectoryError:
        print("ERROR: a directory in your input path is actually a file\n")


def main():

    user_input_filepath = input("Please provide filepath for video you wish to compress. Must be a .y file. Refer to readme info to see how to do this\n")
    user_output_filepath = input("Please provide output filepath + name for output video you wish to compress. (e.g. ~/Desktop/fpgaProject/CompressedVideoFile)\n")
    print(f"Input file you specified: {user_input_filepath} \nOutput you specified : {user_output_filepath}\n")
    frames_to_process = input("Specify the number of frames you wish to convert: \n")

    compress_to_1bpp(
        input_path=user_input_filepath,
        output_path=user_output_filepath,
        width=1920,
        height=1080,
        threshold=128,
        num_frames_process=int(frames_to_process)
    )


if __name__ == "__main__":
    main()