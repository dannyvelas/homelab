terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.83.2"
    }
  }
}

provider "proxmox" {
 endpoint = var.endpoint
 username = var.username
 password = var.password
 insecure = true
}

data "local_file" "ssh_public_key" {
  filename = var.ssh_public_key
}

resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "proxmox"

  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: terraform-provider-proxmox-ubuntu-vm
    package_update: true
    package_upgrade: true
    users:
      - default
      - name: ubuntu
        groups:
          - sudo
        shell: /bin/bash
        ssh_authorized_keys:
          - ${trimspace(data.local_file.ssh_public_key.content)}
        sudo: ALL=(ALL) NOPASSWD:ALL
    packages:
      - qemu-guest-agent
      - net-tools
      - curl
    runcmd:
      # enable qemu-guest-agent
      - systemctl enable qemu-guest-agent
      - systemctl start qemu-guest-agent
      - echo "done" > /tmp/cloud-config.done
      # create mountpoint
      - mkdir -p /mnt/media
      - echo "media_mount /mnt/media virtiofs defaults 0 0" >> /etc/fstab
      - mount -a
    EOF

    file_name = "user-data-cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "ubuntu_vm" {
  name = "terraform-provider-proxmox-ubuntu-vm"
  description = "Managed by Terraform"
  tags        = ["terraform", "ubuntu"]
  node_name   = var.node

  # enable 'Qemu guest agent' so that proxmox can directly communicate with this VM
  # to get its IP address and display it on the console. also so that it can cleanly and
  # gracefully shut it down without having to just send an ACPI signal
  # for us to enable this though, we have to make sure that we are running the qemu-guest-agent
  # in our cloud-init
  agent {
    enabled = true
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 20
  }

  network_device {
    bridge = "vmbr0"
    model = "virtio"
  }

  # this initialization block works because:
  # under the hood, bpg/proxmox created a VM template and stored it in the proxmox "local" storage
  # this template is configured so that when a VM using this template boots for the first time,
  # there will be a special cloud-init drive in it. this allows us to pass data into the VM
  # like SSH keys, hostname, network config, etc
  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "10.0.0.84/24"
        gateway = "10.0.0.1"
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.user_data_cloud_config.id
  }

  # here, we are adding a hardware component to our VM (think of it like plugging in a physical drive)
  # called "media_mount". "media_mount" is a proxmox directory mapping that we created
  # as a resource below
  virtiofs {
    mapping = "media_mount"
    cache = "always"
    direct_io = true
  }
}

# here, we are telling bpg/proxmox to create a VM template that is used by our ubuntu VM.
# we are specifying where that template should be stored.
# we are also specifying the specific cloud image that should be used in this VM template
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "import"
  datastore_id = "local"
  node_name    = var.node
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  # need to rename the file to *.qcow2 to indicate the actual file format for import
  file_name = "noble-server-cloudimg-amd64.qcow2"
}

# create a proxmox directory mapping called "media_mount" which will be hosted at the
# special directory "/mnt/media"
resource "proxmox_virtual_environment_hardware_mapping_dir" "media_mount" {
  name     = "media_mount"
  comment  = "media bind mount"
  map = [
    {
      node = "proxmox"
      path = "/mnt/media"
    },
  ]
}
