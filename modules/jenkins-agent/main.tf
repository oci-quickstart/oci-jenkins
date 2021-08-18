# Init Script Files
data "template_file" "config_agent" {
  template = file("${path.module}/scripts/config.sh")

  vars = {
    jenkins_controller_url = local.jenkins_controller_url
    jenkins_password       = var.jenkins_password
  }
}

locals {
  jenkins_controller_url = "http://${var.jenkins_controller_ip}:${var.jenkins_controller_port}"
}

# Jenkins agents
resource "oci_core_instance" "TFJenkinsAgent" {
  count               = var.number_of_agents
  availability_domain = var.availability_domains[count.index % length(var.availability_domains)]
  compartment_id      = var.compartment_ocid
  display_name        = "${var.label_prefix}${var.agent_display_name}-${count.index + 1}"
  shape               = local.shape

  dynamic "shape_config" {
    for_each = local.is_flex_shape
    content {
      ocpus         = local.flex_shape_ocpus
      memory_in_gbs = local.flex_shape_memory
    }
  }

  dynamic "agent_config" {
    for_each = var.use_bastion_service ? [1] : []
    content {
      are_all_plugins_disabled = false
      is_management_disabled   = false
      is_monitoring_disabled   = false
      plugins_config {
        desired_state = "ENABLED"
        name          = "Bastion"
      }
    }
  }

  create_vnic_details {
    subnet_id        = var.subnet_ids[count.index % length(var.subnet_ids)]
    display_name     = "${var.label_prefix}${var.agent_display_name}-${count.index + 1}"
    assign_public_ip = false
    hostname_label   = "${var.agent_display_name}-${count.index + 1}"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_authorized_keys
  }

  source_details {
    source_id   = var.image_id
    source_type = "image"
  }

  provisioner "file" {
    connection {
      host        = self.private_ip
      agent       = false
      timeout     = "5m"
      user        = var.vm_user
      private_key = var.ssh_private_key

      bastion_host        = var.bastion_host
      bastion_user        = var.bastion_user
      bastion_private_key = var.bastion_private_key
    }

    content     = data.template_file.config_agent.rendered
    destination = "~/config_agent.sh"
  }

  # Register & Launch agent
  provisioner "remote-exec" {
    connection {
      host        = self.private_ip
      agent       = false
      timeout     = "10m"
      user        = var.vm_user
      private_key = var.ssh_private_key

      bastion_host        = var.bastion_host
      bastion_user        = var.bastion_user
      bastion_private_key = var.bastion_private_key
    }

    inline = [
      "sleep 60",
      "sudo chmod +x ~/config_agent.sh",
      "sudo ~/config_agent.sh ${self.display_name}",
    ]
  }
}

