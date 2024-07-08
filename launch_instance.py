"""
This script is used to automate launching instances on Lambda Cloud. 
It allows you to specify the instance type, region, SSH key, and file system to use. 
The script will automatically retry launching the instance if the desired instance 
type is not available in the specified region.

Please note that this script requires a valid Lambda API key to run.
The Instance Types and Regions data is based on the Lambda Cloud API and may change over time.

Lambda is not responsible for any costs incurred by running this script.

Copyright: Lambda Labs 2024
Author: Bryan Gwin
Latest Release: 7/8/2024
License: BSD-3-Clause
"""

import requests
import time
import json


INSTANCE_TYPES_AND_REGIONS = {
    'gpu_8x_h100_sxm5': ["us-west-3"],
    'gpu_1x_h100_pcie': ["us-west-3"],
    'gpu_8x_a100_80gb_sxm4': ["us-midwest-1"],
    'gpu_1x_a10': ["us-east-1", "us-west-1"],
    'gpu_1x_rtx6000': ["us-south-1"],
    'gpu_1x_a100': ["us-south-1"],
    'gpu_1x_a100_sxm4': ["us-east-1", "us-west-2", "asia-south-1"],
    'gpu_2x_a100': ["us-south-1"],
    'gpu_4x_a100': ["us-south-1"],
    'gpu_8x_a100': [
        "me-west-1",
        "asia-northeast-2",
        "us-west-2",
        "us-west-1",
        "europe-central-1",
        "asia-northeast-1",
        "us-east-1",
    ],
    'gpu_1x_a6000': ["us-south-1"],
    'gpu_2x_a6000': ["us-south-1"],
    'gpu_4x_a6000': ["us-south-1"],
    'gpu_8x_v100': ["us-south-1"],
    'cpu_4x_general': ["not available"],
    'gpu_8x_h100_sxm5raidz1': ["us-south-2"],
}


def get_instance_types():
    """Fetches the instance types available."""
    return list(INSTANCE_TYPES_AND_REGIONS.keys())


def get_regions_for_instance_type(instance_type):
    """Fetches the regions available for the specified instance type."""
    regions = INSTANCE_TYPES_AND_REGIONS.get(instance_type)
    if regions:
        return regions
    else:
        return "Instance type not found"


def get_available_instances(api_key):
    """Fetches available instances and their details."""
    response = requests.get(
        "https://cloud.lambdalabs.com/api/v1/instance-types",
        auth=(api_key, ""),
        timeout=10,
    )
    return response.json()


def get_ssh_keys(api_key):
    """Fetches available SSH keys."""
    response = requests.get(
        "https://cloud.lambdalabs.com/api/v1/ssh-keys",
        auth=(api_key, ""),
        timeout=10,
    )
    data = response.json()
    ssh_key_names = [key['name'] for key in data['data']]
    return ssh_key_names


def get_file_systems(api_key):
    """Fetches available file systems."""
    response = requests.get(
        "https://cloud.lambdalabs.com/api/v1/file-systems",
        auth=(api_key, ""),
        timeout=10,
    )
    data = response.json()
    filesystem_names = [key['name'] for key in data['data']]
    return filesystem_names


def launch_instance(
    api_key,
    region_name,
    desired_instance_type,
    ssh_key_name,
    file_system_name,
    quantity,
):
    """Launches an instance with the specified configuration."""
    data = {
        "region_name": region_name,
        "instance_type_name": desired_instance_type,
        "ssh_key_names": [ssh_key_name],
        "file_system_names": [file_system_name] if file_system_name else [],
        "quantity": quantity,
    }
    response = requests.post(
        "https://cloud.lambdalabs.com/api/v1/instance-operations/launch",
        auth=(api_key, ""),
        headers={"Content-Type": "application/json"},
        data=json.dumps(data),
        timeout=100,
    )

    response_data = response.json()
    return response_data


def get_valid_instance_types(api_key):
    """Retrieves a list of all available instance types."""
    instance_data = get_available_instances(api_key)
    instances = instance_data.get("data", {})
    return list(instances.keys())


def main():
    # API key input
    print("Paste in your Lambda API key.")
    print("If you do not have an API key you can generate one by clicking ")
    print("'Generate API key' under 'API keys'in your Lambda Cloud dashboard.")
    
    # API key input loop
    while True:
        api_key = input("API key: ")
        valid_instance_types = get_valid_instance_types(api_key)
        if valid_instance_types == []:
            print("API key is invalid or has no permissions.")
        else:
            break
        
    # Instance type selection
    instance_types = get_instance_types()
    print("\nAvailable instance types:", instance_types, "\n")
    while True:
        desired_instance_type = input("Enter the desired instance type: ")
        if desired_instance_type not in instance_types:
            print("Invalid instance type. " "Please choose from the available types.")
        else:
            break
        
    # Region selection
    print(f"\nAvailable regions for {desired_instance_type}: ")
    available_regions = get_regions_for_instance_type(desired_instance_type)
    print(available_regions)
    while True:
        region_name = input("Region name: ")
        if region_name != "" and region_name not in available_regions:
            print("Invalid region name. Please choose from the available regions.")
        else:
            break
    
    # SSH key selection
    ssh_key_names = get_ssh_keys(api_key)
    print(f"\nAvailable SSH keys:\n {ssh_key_names}")
    while True:
        ssh_key_name = input("Enter the SSH key name you would like to use: ")
        if ssh_key_name in ssh_key_names:
            break
        else:
            print("Invalid SSH key name. Please choose from the available SSH keys.")

    # File system selection
    while True:
        use_filesystem = input("Would you like to attach a file system? (y/n): ")
        if use_filesystem.lower() == "y":
            filesystem_names = get_file_systems(api_key)
            print(f"\nAvailable file systems:\n {filesystem_names}")
            while True:
                filesystem_name = input("Enter filesystem name you would like to use: ")
                if filesystem_name in filesystem_names:
                    break
                else:
                    print("Invalid filesystem name. Please choose from the available file systems.")
            break
        elif use_filesystem.lower() == "n":
            filesystem_name = None  # Changed from "" to None as per previous suggestion
            break
        else:
            print("Invalid input. Please enter 'y' or 'n'.")
            
    # Quantity selection
    while True:
        quantity = input("Enter the number of instances you would like to launch (1-9): ")
        if quantity.isdigit():
            number = int(quantity)
            if 1 <= number <= 9:
                break
            else:
                print("Invalid input. Please enter a number between 1 and 9.")
        else:
            print("Invalid input. Please enter a number between 1 and 9.")

    # Instance launch loop
    continue_loop = True
    while continue_loop:
        if region_name == "":
            region_name = "us-south-1"
            desired_instance_type = "gpu_8x_h100_sxm5"
            launch_response = launch_instance(
                api_key,
                region_name,
                desired_instance_type,
                ssh_key_name,
                filesystem_name,
                quantity,
            )
            if (
                "error" in launch_response
                and launch_response["error"].get("code") != "instance-operations/launch/insufficient-capacity"
            ):
                print("Error launching instance:", launch_response["error"])
                break
            
        # Attempt to launch the instance
        launch_response = launch_instance(
            api_key,
            region_name,
            desired_instance_type,
            ssh_key_name,
            filesystem_name,
            quantity,
        )
        if (
            "error" in launch_response
            and launch_response["error"].get("code") != "instance-operations/launch/insufficient-capacity"
        ):
            print("Error launching instance:", launch_response["error"])
            break
        elif "data" in launch_response:
            print("Instance launched successfully!")
            print("Launch response:", launch_response["data"])
            break

        while True:
            # Get instance data
            instance_data = get_available_instances(api_key)
            instances = instance_data.get("data", {})

            instance_details = instances.get(desired_instance_type)
            if instance_details:
                regions_available = instance_details.get("regions_with_capacity_available", [])
                # Check if the desired instance type is available
                if regions_available:
                    if region_name == "":
                        region_name = regions_available[0]["name"]
                    ssh_key_name = input("SSH key name: ")

                    print(f"Launching {desired_instance_type} in region {region_name}...")
                    launch_response = launch_instance(
                        api_key,
                        region_name,
                        desired_instance_type,
                        ssh_key_name,
                        filesystem_name,
                        quantity,
                    )

                    if launch_response["success"]:
                        print("Launch response:", launch_response["data"])
                        continue_loop = False
                        break
                    else:
                        print(
                            "Error launching instance:",
                            launch_response["error"],
                        )
                        continue_loop = False
                        break

                else:
                    print(f"Instance type {desired_instance_type} not found. Retrying in 2 seconds...")
            time.sleep(2)  # Wait to comply with API rate limit and retry interval
        if not continue_loop:
            break


if __name__ == "__main__":
    main()
