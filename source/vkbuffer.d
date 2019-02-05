module vkbuffer;

import core.stdc.stdint;
import core.stdc.stdio;

import vkcontext;

import glfw;
import utility;
import vk;
 
////////////////////////////////////////////////////////////////////////////////
uint32_t FindMemoryType(
  ref Framework fw
, uint32_t typeFilter
, VkMemoryPropertyFlags properties
) {
  VkPhysicalDeviceMemoryProperties memProperties;
  fw.physicalDevice.vkGetPhysicalDeviceMemoryProperties(&memProperties);

  foreach (i; 0 .. memProperties.memoryTypeCount) {
    if (
        (typeFilter & (1 << i))
     && (memProperties.memoryTypes[i].propertyFlags & properties) == properties
    ) {
      return i;
    }
  }

  false.EnforceAssert("Failed to find a memory type");
  assert(false);
}

////////////////////////////////////////////////////////////////////////////////
void CreateBuffer(
  ref Framework fw
, ref VkBufferCreateInfo bufferInfo
, VkMemoryPropertyFlags properties
, VkBuffer * buffer
, VkDeviceMemory * bufferMemory
) {
  // create buffer
  fw.device
    .vkCreateBuffer(&bufferInfo, null, buffer)
    .EnforceVk;

  // -- get memory requirements 
  VkMemoryRequirements memoryRequirements;
  fw.device
    .vkGetBufferMemoryRequirements(*buffer, &memoryRequirements);

  { // -- allocate buffer
    VkMemoryAllocateInfo info = {
      sType: VkStructureType.memoryAllocateInfo
    , pNext: null
    , allocationSize: memoryRequirements.size
    , memoryTypeIndex:
        fw.FindMemoryType(memoryRequirements.memoryTypeBits, properties)
    };

    fw.device
      .vkAllocateMemory(&info, null, bufferMemory)
      .EnforceVk;
  }

  fw.device
    .vkBindBufferMemory(*buffer, *bufferMemory, 0);
}
