###
# provider
###
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  zone = "ru-central1-a"
}

###
# common
###
resource "yandex_vpc_network" "edu-network" {
  name = "edu-network"
}

resource "yandex_vpc_subnet" "subnet-ru-central1-a" {
  name           = "edu-network-ru-central1-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.edu-network.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

###
# keycloak
###
# Public static IP
resource "yandex_vpc_address" "keycloak-nat" {
  name = "keycloak-nat"

  external_ipv4_address {
    zone_id = "ru-central1-a"
  }
}

# VM
resource "yandex_compute_instance" "keycloak" {
  name        = "keycloak"
  platform_id = "standard-v1"
  zone        = "ru-central1-a"
  allow_stopping_for_update = true

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = "fd8ni66vim3em9jgua7g"
      size = 10
    }
  }

  network_interface {
    subnet_id = "${yandex_vpc_subnet.subnet-ru-central1-a.id}"
    nat       = true
    nat_ip_address = yandex_vpc_address.keycloak-nat.external_ipv4_address[0].address
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
  }

  connection {
    type     = "ssh"
    user     = "ubuntu"
    private_key = "${file("~/.ssh/id_ed25519")}"
    host     = yandex_compute_instance.keycloak.network_interface.0.nat_ip_address
  }

  provisioner "file" {
    source      = "script.sh"
    destination = "/tmp/script.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo bash /tmp/script.sh"
    ]
  }
}

# Print keycloak url
output "url_keycloak" {
  value = "https://keycloak.${yandex_compute_instance.keycloak.network_interface.0.nat_ip_address}.sslip.io"
}

###
# DontSueMe
###
# Service account
resource "yandex_iam_service_account" "dontsueme-sa" {
  name        = "dontsueme-sa"
  description = "Service account for DontSueMe"
}

# Service account static key
resource "yandex_iam_service_account_static_access_key" "dontsueme-sa-static-key" {
  service_account_id = yandex_iam_service_account.dontsueme-sa.id
  description        = "DontSueMe static access key for object storage"
}

# Lockbox secret
resource "yandex_lockbox_secret" "dontsueme-sa-static-key" {
  name = "DontSueMe sa static key"
}

# Lockbox secret version
resource "yandex_lockbox_secret_version" "dontsueme-sa-static-key-version" {
  secret_id = yandex_lockbox_secret.dontsueme-sa-static-key.id
  entries {
    key        = "access_key"
    text_value = yandex_iam_service_account_static_access_key.dontsueme-sa-static-key.access_key
  }
  entries {
    key        = "secret_key"
    text_value = yandex_iam_service_account_static_access_key.dontsueme-sa-static-key.secret_key
  }
}

# Public static IP
resource "yandex_vpc_address" "dontsueme-nat" {
  name = "dontsueme-nat"

  external_ipv4_address {
    zone_id = "ru-central1-a"
  }
}

# VM
resource "yandex_compute_instance" "dontsueme" {
  name        = "dontsueme"
  platform_id = "standard-v1"
  zone        = "ru-central1-a"

  service_account_id = yandex_iam_service_account.dontsueme-sa.id

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = "fd8emvfmfoaordspe1jr"
      size     = 10
    }
  }

  network_interface {
    subnet_id      = yandex_vpc_subnet.subnet-ru-central1-a.id
    nat            = true
        nat_ip_address = yandex_vpc_address.dontsueme-nat.external_ipv4_address[0].address
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
  }

  allow_stopping_for_update = true
  scheduling_policy {
    preemptible = true
  }
}

resource "null_resource" "dontsueme-provisioner" {
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = "${file("~/.ssh/id_ed25519")}"
    host        = yandex_compute_instance.dontsueme.network_interface.0.nat_ip_address
  }

  triggers = {
    script_sha1 = "${sha1(file("dontsueme.sh"))}"
  }

  provisioner "file" {
    source      = "dontsueme.sh"
    destination = "/tmp/dontsueme.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo bash /tmp/dontsueme.sh"
    ]
  }
}

# Print DontSueMe IP
output "ip_dontsueme" {
  value = yandex_compute_instance.dontsueme.network_interface.0.nat_ip_address
}

# Print DontSueMe URL
output "url_dontsueme" {
  value = "https://dontsueme.${yandex_compute_instance.dontsueme.network_interface.0.nat_ip_address}.sslip.io"
}
