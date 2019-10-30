#resource "null_resource" "image_copied" {
#  provisioner "local-exec" {
#    command = "echo 'IBM Cloud Private Image has been successfully copied. Loading resource ID : '${var.image_copy_finished}"
#  }
#}
resource "null_resource" "image_load" {
  # Only do an image load if we have provided a location. Presumably if not we'll be loading from private registry server
  count = "${var.image_location != "" ? 1 : 0}"
 # depends_on = ["null_resource.image_copied"]

  connection {
    host          = "${var.boot_ipv4_address_private}"
    user          = "icpdeploy"
    private_key   = "${var.boot_private_key_pem}"
    bastion_host  = "${var.private_network_only ? var.boot_ipv4_address_private : var.boot_ipv4_address}"
  }

  provisioner "file" {
    source = "${path.module}/scripts/load_image.sh"
    destination = "/tmp/load_image.sh"
  }

  provisioner "remote-exec" {
    # We need to wait for cloud init to finish it's boot sequence.
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do sleep 1; done",
      "sudo mv /tmp/load_image.sh /opt/ibm/scripts/",
      "sudo chmod a+x /opt/ibm/scripts/load_image.sh",
      "/opt/ibm/scripts/load_image.sh -p ${var.image_location} -r ${var.registry_server} -u ${var.docker_username} -c ${var.docker_password}",
      "sudo touch /opt/ibm/.imageload_complete"
    ]
  }
}

resource "null_resource" "image_load_finished" {
  depends_on = ["null_resource.image_load"]
  provisioner "local-exec" {
    command = "echo 'IBM Cloud Private Image has been successfully loaded. '"
  }
}