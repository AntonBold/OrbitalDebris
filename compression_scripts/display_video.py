import numpy as np
import cv2

def display_1bpp_video(
    filename,
    width,
    height,
    fps=60
):
    pixels_per_frame = width * height
    packed_bytes_per_frame = pixels_per_frame // 8

    with open(filename, "rb") as f:
        frame_index = 0
        while True:

            # Read one packed frame
            packed = f.read(packed_bytes_per_frame)
            if len(packed) < packed_bytes_per_frame:
                break  # end of file

            # Convert bytes → NumPy array
            packed_arr = np.frombuffer(packed, dtype=np.uint8)

            # Unpack bits (MSB first)
            bits = np.unpackbits(packed_arr, bitorder='big')

            # Reshape to 2D image
            frame = bits.reshape((height, width))

            # Scale 0/1 → 0/255 for display
            frame_vis = (frame * 255).astype(np.uint8)

            # Display
            cv2.imshow("1-bit Thresholded Video", frame_vis)
            if frame_index == 0:
                print("Paused on first frame. Press any key to continue...")
                cv2.waitKey(0)  # wait indefinitely
                first_frame = False
            else:
                if cv2.waitKey(int(1000 / fps)) & 0xFF == ord('q'):
                    break

            frame_index += 1

    cv2.destroyAllWindows()
    print(f"Displayed {frame_index} frames.")




if __name__ == "__main__":
    print("INFO: display pauses on first frame. Must press any key to continue\n")
    print("Press q while viewing video to quit\n")
    user_file = input("Provide name of file you wish to display\n")
    user_fps = int(input("Please provide desired FPS\n"))
    display_1bpp_video(
        filename=user_file,
        width=1920,
        height=1080,
        fps=user_fps
    )