module vkimage;

import vk;
import vkcontext;
import utility;

import core.stdc.stdint;

////////////////////////////////////////////////////////////////////////////////
struct Image {
  VkFormat format;
  VkImage image;
  VkDeviceMemory memory;
  VkImageView imageView;
  VkSampler sampler;
}

void Create (
  ref Framework fw
, ref Image image
, VkImageType imageType
, VkFormat format
, VkExtent3D extent
, VkImageTiling tiling
, VkImageUsageFlags usageFlags
, VkMemoryPropertyFlags memoryProperties
);

////////////////////////////////////////////////////////////////////////////////
Image CreateImage (
  ref Framework fw
, VkImageType imageType
, VkFormat format
, VkExtent3D extent
, VkImageTiling tiling
, VkImageUsageFlags usageFlags
, VkMemoryPropertyFlags memoryProperties
) {
  Image image;
  image.format = format;

  VkImageCreateInfo imageCreateInfo = {
    sType:                 VkStructureType.imageCreateInfo
  , pNext:                 null
  , flags:                 0
  , imageType:             imageType
  , format:                format
  , extent:                extent
  , mipLevels:             1
  , arrayLayers:           1
  , samples:               VkSampleCountFlag.i1Bit
  , tiling:                tiling
  , usage:                 usageFlags
  , sharingMode:           VkSharingMode.exclusive
  , queueFamilyIndexCount: 0
  , pQueueFamilyIndices:   null
  , initialLayout:         VkImageLayout.undefined
  };

  fw.device
    .vkCreateImage(
      &imageCreateInfo
    , null
    , &image.image
    ).EnforceVk;

  VkMemoryRequirements memoryRequirements;
  fw.device.vkGetImageMemoryRequirements(image.image, &memoryRequirements);

  VkMemoryAllocateInfo memoryAllocateInfo = {
    sType:           VkStructureType.memoryAllocateInfo
  , pNext:           null
  , allocationSize:  memoryRequirements.size
  , memoryTypeIndex:
      GetMemoryType(
        fw.physicalDeviceMemoryProperties
      , memoryRequirements
      , memoryProperties
      )
  };

  fw.device
    .vkAllocateMemory(
      &memoryAllocateInfo
    , null
    , &image.memory
    ).EnforceVk;

  fw.device
    .vkBindImageMemory(
      image.image
    , image.memory
    , 0
    ).EnforceVk;

  return image;
}

////////////////////////////////////////////////////////////////////////////////
void CreateImageView (
  ref Framework fw
, ref Image image
, VkImageViewType viewType
, VkFormat format
, VkImageSubresourceRange subresourceRange
) {
  VkImageViewCreateInfo imageViewCreateInfo = {
     sType:      VkStructureType.imageViewCreateInfo
  ,  pNext:      null
  ,  flags:      0
  ,  image:      image.image
  ,  viewType:   viewType
  ,  format:     format
  ,  components:
        VkComponentMapping(
          VkComponentSwizzle.r
        , VkComponentSwizzle.g
        , VkComponentSwizzle.b
        , VkComponentSwizzle.a
          )
  , subresourceRange: subresourceRange
  };

  fw.device
    .vkCreateImageView(
      &imageViewCreateInfo
    , null
    , &image.imageView
    ).EnforceVk;
}

////////////////////////////////////////////////////////////////////////////////
void TransitionImageLayout (
  ref Framework fw
, ref Image image
, VkFormat format
, VkImageLayout oldLayout
, VkImageLayout newLayout
) {
  auto commandBuffer = ScopedSingleTimeCommandBuffer(fw);

  VkImageSubresourceRange subresourceRange = {
    aspectMask:     VkImageAspectFlag.colorBit
  , baseMipLevel:   0
  , levelCount:     1
  , baseArrayLayer: 0
  , layerCount:     1
  };

  VkImageMemoryBarrier barrier = {
    sType: VkStructureType.imageMemoryBarrier
  , pNext: null
  , srcAccessMask: 0
  , dstAccessMask: 0
  , oldLayout: oldLayout
  , newLayout: newLayout
  , srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED
  , dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED
  , image: image.image
  , subresourceRange: subresourceRange
  };

  VkPipelineStageFlags sourceStage;
  VkPipelineStageFlags destinationStage;

  barrier.subresourceRange.aspectMask = VkImageAspectFlag.colorBit;
  if (newLayout == VkImageLayout.depthStencilAttachmentOptimal) {
    barrier.subresourceRange.aspectMask = VkImageAspectFlag.depthBit;

    // TODO allow stencil buffer
    // if (hasStencilComponent(format)) {
    //   barrier.subresourceRange.aspectMask |= VK_IMAGE_ASPECT_STENCIL_BIT;
    // }
  }

  if (
       oldLayout == VkImageLayout.undefined
    && newLayout == VkImageLayout.transferDstOptimal
  ) {
    barrier.srcAccessMask = 0;
    barrier.dstAccessMask = VkAccessFlag.transferWriteBit;

    sourceStage = VkPipelineStageFlag.topOfPipeBit;
    destinationStage = VkPipelineStageFlag.transferBit;
  }
  else if (
      oldLayout == VkImageLayout.transferDstOptimal
   && newLayout == VkImageLayout.shaderReadOnlyOptimal
  ) {
    barrier.srcAccessMask = VkAccessFlag.transferWriteBit;
    barrier.dstAccessMask = VkAccessFlag.shaderReadBit;

    sourceStage = VkPipelineStageFlag.transferBit;
    destinationStage = VkPipelineStageFlag.fragmentShaderBit;
  }
  else if (
      oldLayout == VkImageLayout.undefined
   && newLayout == VkImageLayout.depthStencilAttachmentOptimal
  ) {
    barrier.srcAccessMask = 0;
    barrier.dstAccessMask =
        VkAccessFlag.depthStencilAttachmentReadBit
      | VkAccessFlag.depthStencilAttachmentWriteBit;

    sourceStage = VkPipelineStageFlag.topOfPipeBit;
    destinationStage = VkPipelineStageFlag.earlyFragmentTestsBit;
  }
  else
  {
    import core.stdc.stdio;
    "Unsupported layout transition".printf;
  }

  commandBuffer.cmdBuffer.vkCmdPipelineBarrier(
    /*srcStageMask            */ sourceStage
  , /*dstStageMask            */ destinationStage
  , /*dependencyFlags         */ 0
  , /*memoryBarrierCount      */ 0
  , /*pMemoryBarriers         */ null
  , /*bufferMemoryBarrierCount*/ 0
  , /*pBufferMemoryBarriers   */ null
  , /*imageMemoryBarrierCount */ 1
  , /*pImageMemoryBarriers    */ &barrier
  );
}

////////////////////////////////////////////////////////////////////////////////
void CopyBufferToImage(
  ref Framework fw
, ref Image image
, VkBuffer buffer
, uint32_t width
, uint32_t height
) {
  ScopedSingleTimeCommandBuffer cmdBuffer;

  VkImageSubresourceLayers subresourceLayers = {
    aspectMask:     VkImageAspectFlag.colorBit
  , mipLevel:       0
  , baseArrayLayer: 0
  , layerCount:     1
  };

  VkBufferImageCopy region = {
    bufferOffset: 0
  , bufferRowLength: 0
  , bufferImageHeight: 0
  , imageSubresource: subresourceLayers 
  , imageOffset: VkOffset3D(0, 0, 0)
  , imageExtent: VkExtent3D(width, height, 1)
  };

  cmdBuffer.cmdBuffer
    .vkCmdCopyBufferToImage(
      buffer
    , image.image
    , VkImageLayout.transferDstOptimal
    , 1
    , &region
    );
}
