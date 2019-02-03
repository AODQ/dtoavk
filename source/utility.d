module utility;

import core.stdc.stdint;
import core.stdc.stdio;

import neobc.array;

import glfw;
import vk;

void EnforceAssert(
  T
, string PF = __PRETTY_FUNCTION__
, string FP = __FILE_FULL_PATH__
, int LC    = __LINE__
)(
  T status
, string err = ""
) {
  if ( !cast(bool)(status) ) {
    import core.stdc.stdlib;
    import core.stdc.signal;
    printf("assert failed: %s: %s ; %d: %s\n", FP.ptr, PF.ptr, LC, err.ptr);
    raise(SIGABRT);
    exit(-1);
  }
}

void EnforceVk(
  string PF = __PRETTY_FUNCTION__
, string FP = __FILE_FULL_PATH__
, int LC    = __LINE__
)(VkResult status) {
  if ( status != VkResult.success ) {
    import core.stdc.stdlib;
    import core.stdc.signal;
    printf("assert failed: %s: %s ; %d\n", FP.ptr, PF.ptr, LC);
    raise(SIGABRT);
    exit(-1);
  }
}

uint32_t GetMemoryType(
  VkPhysicalDeviceMemoryProperties physicalDeviceMemoryProperties
, ref VkMemoryRequirements memoryRequirements
, VkMemoryPropertyFlags memoryProperties
) {
  foreach ( memTypeIdx; 0 .. VK_MAX_MEMORY_TYPES ) {
    if ( !(memoryRequirements.memoryTypeBits & (1 << memTypeIdx)) )
      continue;

    auto physicalDevicePropertyFlags
      = physicalDeviceMemoryProperties.memoryTypes[memTypeIdx].propertyFlags;

    if ( (physicalDevicePropertyFlags & memoryProperties) == memoryProperties )
      return memTypeIdx;
  }

  return 0;
}

Array!(ArrayType) GetVkArray(
  string fnName
, bool hasEnforce
, ArrayType
, FnParams...
)(ref FnParams params) {
  uint32_t arrayLength;

  // TODO ; use format when BetterC allows it
  mixin(
    (hasEnforce?`EnforceVk(`:`(`)
  ~ fnName
  ~ `(params, &arrayLength, null));`);
  auto array = Array!(ArrayType)(arrayLength);
  mixin(
    (hasEnforce?`EnforceVk(`:`(`)
  ~ fnName
  ~ `(params, &arrayLength, array.ptr));`);

  return array;
}

alias GetPhysicalDevices =
  GetVkArray!("vkEnumeratePhysicalDevices", true, VkPhysicalDevice, VkInstance);

alias GetPhysicalDeviceQueueFamilyProperties =
  GetVkArray!(
    "vkGetPhysicalDeviceQueueFamilyProperties"
  , false
  , VkQueueFamilyProperties
  , VkPhysicalDevice
  );


alias GetPresentModes =
  GetVkArray!(
    "vkGetPhysicalDeviceSurfacePresentModesKHR"
  , false
  , VkPresentModeKHR
  , VkPhysicalDevice
  , VkSurfaceKHR
  );

alias GetSurfaceFormats =
  GetVkArray!(
    "vkGetPhysicalDeviceSurfaceFormatsKHR"
  , false
  , VkSurfaceFormatKHR
  , VkPhysicalDevice
  , VkSurfaceKHR
  );

alias vkGetSwapchainImagesKHRNeo =
  GetVkArray!(
    "vkGetSwapchainImagesKHR"
  , false
  , VkImage
  , VkDevice
  , VkSwapchainKHR
  );

Array!(VkImageView) GetSwapchainImageViews(
  ref VkDevice device
, ref Array!(VkImage) swapchainImages
, ref VkSurfaceFormatKHR surfaceFormat
) {
  auto imageViews = Array!(VkImageView)(swapchainImages.length);
  foreach ( iter; 0 .. swapchainImages.length ) {
    auto swapchainImage = swapchainImages[iter];

    VkImageSubresourceRange subresourceRange = {
      aspectMask:     VkImageAspectFlag.colorBit
    , baseMipLevel:   0
    , levelCount:     1
    , baseArrayLayer: 0
    , layerCount:     1
    };

    VkImageViewCreateInfo imageViewCreateInfo = {
      sType:            VkStructureType.imageViewCreateInfo
    , pNext:            null
    , flags:            0
    , image:            swapchainImage
    , viewType:         VkImageViewType.i2D
    , format:           surfaceFormat.format
    , components:       {}
    , subresourceRange: subresourceRange
    };

    EnforceVk(vkCreateImageView(
      device
    , &imageViewCreateInfo
    , null
    , &imageViews[iter]
    ));
  }
  return imageViews;
}


void ImageBarrier(
  ref VkCommandBuffer commandBuffer
, ref VkImage image
, ref VkImageSubresourceRange subresourceRange
, VkAccessFlags srcAccessMask
, VkAccessFlags dstAccessMask
, VkImageLayout oldLayout
, VkImageLayout newLayout
) {
  VkImageMemoryBarrier imageMemoryBarrier = {
    sType:               VkStructureType.imageMemoryBarrier
  , pNext:               null
  , srcAccessMask:       srcAccessMask
  , dstAccessMask:       dstAccessMask
  , oldLayout:           oldLayout
  , newLayout:           newLayout
  , srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED
  , dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED
  , image:               image
  , subresourceRange:    subresourceRange
  };

  commandBuffer.vkCmdPipelineBarrier(
    VkPipelineStageFlag.allCommandsBit
  , VkPipelineStageFlag.allCommandsBit
  , 0 // dependencyFlags
  , 0 // memoryBarrierCount
  , null // pMemoryBarriers
  , 0 // bufferMemoryBarrierCount
  , null // pBufferMemoryBarriers
  , 1 // imageMemoryBarrierCount
  , &imageMemoryBarrier // pImageMemoryBarriers
  );
}

void GetRequiredGlfwExtensions(ref Array!(const(char)*) extensions) {
  uint32_t requiredExtensionLength;
  const(char)** requiredExtensions =
    glfwGetRequiredInstanceExtensions(&requiredExtensionLength);

  foreach ( size_t i; 0 .. requiredExtensionLength ) {
    extensions ~= requiredExtensions[i];
  }
}
