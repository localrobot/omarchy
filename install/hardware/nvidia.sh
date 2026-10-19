if lspci | grep -qi 'nvidia'; then
  omarchy-pkg-add nvidia-open-dkms nvidia-utils

  # Configure modprobe for dedicated compute: stub display/modeset modules and enable open RM
  mkdir -p /etc/modprobe.d
  cat > /etc/modprobe.d/nvidia.conf <<'EOF'
# Dedicated AI compute configuration for NVIDIA RTX GPU
# Prevent nvidia display/modesetting modules from creating DRM device nodes
install nvidia_drm /bin/true
install nvidia_modeset /bin/true
options nvidia NVreg_OpenRmEnableUnsupportedGpus=1
EOF

  # Configure mkinitcpio for early loading: AMD for display, NVIDIA for compute
  mkdir -p /etc/mkinitcpio.conf.d
  cat > /etc/mkinitcpio.conf.d/nvidia.conf <<'EOF'
MODULES+=(amdgpu nvidia nvidia_uvm)
EOF
fi
