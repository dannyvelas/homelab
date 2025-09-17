terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.83.2"
    }
  }
}

provider "proxmox" {
 endpoint = var.pm_endpoint
 username = var.username
 password = var.password
 insecure = true
}

data "local_file" "ssh_public_key" {
  filename = var.ssh_public_key
}

resource "proxmox_virtual_environment_vm" "ubuntu_vm" {
  name = "terraform-provider-proxmox-ubuntu-vm"
  description = "Managed by Terraform"
  tags        = ["terraform", "ubuntu"]
  node_name   = var.pm_node

  clone {
    vm_id = 9000
    full = true
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }
  
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 8
  }

  network_device {
    bridge = "vmbr0"
    model = "virtio"
  }

  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [trimspace(data.local_file.ssh_public_key.content)]
    }
  }
}
