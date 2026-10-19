# Install Vulkan driver for AMD Radeon display GPU
# (NVIDIA card is dedicated to CUDA/AI compute and invisible to graphics)

if lspci | grep -iE "(VGA|Display).*AMD" > /dev/null; then
  omarchy-pkg-add vulkan-radeon
fi
