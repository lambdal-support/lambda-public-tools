# This script tests if PyTorch is utilizing all available GPUs on the machine.

# Copyright Lambda Labs Inc. 2024
# License: BSD-3-Clause
# Author: Bryan Gwin

import subprocess
import torch


def get_gpu_count():
    try:
        result = subprocess.run(["nvidia-smi", "-L"], stdout=subprocess.PIPE)
        gpu_count = len(result.stdout.decode().strip().split("\n"))
        return gpu_count
    except Exception as e:
        print("Error occurred while getting GPU count:", e)
        return 0


def main():
    # Get the number of available GPUs on machine
    global_device_count = get_gpu_count()
    print(f"Number of available GPUs: {global_device_count}")

    # Get the number of GPUs being utilized by PyTorch
    cuda_device_count = torch.cuda.device_count()
    print(
        f"Number of available GPUs being used by PyTorch: {cuda_device_count}"
    )

    if global_device_count == 0:
        print(
            "No GPUs available. Make sure NVIDIA drivers are properly "
            "installed."
        )
        return
    elif global_device_count != cuda_device_count:
        print("Not all GPUs are being utilized by PyTorch.")
        return

    # Utilize all available GPUs
    print("Testing GPU utilization...")
    for i in range(cuda_device_count):
        device = torch.device(f"cuda:{i}")
        print(f"Using GPU {i}: {torch.cuda.get_device_name(i)}")
        # Run a simple computation on each GPU
        with torch.cuda.device(device):
            a = torch.randn(1000, 1000).cuda()
            b = torch.randn(1000, 1000).cuda()
            c = torch.matmul(a, b)
            # Ensure the computation finished cleanly
            try:
                torch.cuda.synchronize()
            except Exception as e:
                print(f"Error occurred while utilizing GPU {i}: {e}")
                print(f"GPU {i} is not being utilized correctly.")
                return

    print("All GPUs are utilized.")


if __name__ == "__main__":
    main()
