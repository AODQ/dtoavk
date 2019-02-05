module rasterizer;

import utility;
import vk;
import vkbuffer;
import vkcontext;
import vkimage;

import neobc.array;

import core.stdc.stdint;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;

////////////////////////////////////////////////////////////////////////////////
struct MatrialObj
{
  float[3] ambient       = [0.1f, 0.1f, 0.1f];
  float[3] diffuse       = [0.7f, 0.7f, 0.7f];
  float[3] specular      = [1.0f, 1.0f, 1.0f];
  float[3] transmittance = [0.0f, 0.0f, 0.0f];
  float[3] emission      = [0.0f, 0.0f, 0.0f];
  float shininess = 0.0f;
  float ior = 1.0f;
  float dissolve = 1.0f;
  int illum = 0;
  int textureID = -1;
};

////////////////////////////////////////////////////////////////////////////////
struct Vertex
{
  float[3] origin;
  float[3] normal;
  float[3] color;
  float[2] texCoord;
  int materialId = 0;

  static VkVertexInputBindingDescription GetBindingDescription() {
    VkVertexInputBindingDescription description = {
      binding: 0
    , stride: Vertex.sizeof
    , inputRate: VkVertexInputRate.vertex
    };

    return description;
  }

  static Array!(VkVertexInputAttributeDescription)
      GetAttributBindingDescriptions()
  {
    auto descriptions = Array!(VkVertexInputAttributeDescription)(5);

    descriptions[0].binding  = 0;
    descriptions[0].location = 0;
    descriptions[0].format   = VkFormat.r32g32b32Sfloat;
    descriptions[0].offset   = Vertex.origin.offsetof;

    descriptions[1].binding  = 0;
    descriptions[1].location = 1;
    descriptions[1].format   = VkFormat.r32g32b32Sfloat;
    descriptions[1].offset   = Vertex.normal.offsetof;

    descriptions[2].binding  = 0;
    descriptions[2].location = 2;
    descriptions[2].format   = VkFormat.r32g32b32Sfloat;
    descriptions[2].offset   = Vertex.color.offsetof;

    descriptions[3].binding  = 0;
    descriptions[3].location = 3;
    descriptions[3].format   = VkFormat.r32g32Sfloat;
    descriptions[3].offset   = Vertex.texCoord.offsetof;

    descriptions[4].binding  = 0;
    descriptions[4].location = 4;
    descriptions[4].format   = VkFormat.r32Sint;
    descriptions[4].offset   = Vertex.materialId.offsetof;

    return descriptions;
  }
}

////////////////////////////////////////////////////////////////////////////////
private struct UniformBufferObject {
  float[16] model;
  float[16] view;
  float[16] projection;
  float[16] modelIt;
};

////////////////////////////////////////////////////////////////////////////////
struct Rasterizer {
public:
  VkDescriptorSetLayout descriptorSetLayout;
  VkPipelineLayout      pipelineLayout;
  VkPipeline            graphicsPipeline;
  VkDescriptorSet       descriptorSet;

  uint32_t indices;
  uint32_t vertices;

  VkBuffer vertexBuffer;
  VkDeviceMemory vertexBufferMemory;

  VkBuffer indexBuffer;
  VkDeviceMemory indexBufferMemory;

  VkBuffer uniformBuffer;
  VkDeviceMemory uniformBufferMemory;

  VkBuffer matColorBuffer;
  VkDeviceMemory matColorBufferMemory;

  VkExtent2D framebufferSize;

  Array!(VkImage)        textureImage;
  Array!(VkDeviceMemory) textureImageMemory;
  Array!(VkImageView)    textureImageView;
  Array!(VkSampler)      textureSampler;
}

////////////////////////////////////////////////////////////////////////////////
void CreateDescriptorSetLayout(ref Framework fw, ref Rasterizer rs) {
  auto bindings = Array!(VkDescriptorSetLayoutBinding)(3);
  { // -- matrices
    VkDescriptorSetLayoutBinding binding = {
      binding: 0
    , descriptorType: VkDescriptorType.uniformBuffer
    , descriptorCount: 1
    , stageFlags: VkShaderStageFlag.vertexBit
    , pImmutableSamplers: null
    };

    bindings[0] = binding;
  }

  { // -- material color
    VkDescriptorSetLayoutBinding binding = {
      binding:            1
    , descriptorType:     VkDescriptorType.storageBuffer
    , descriptorCount:    1
    , stageFlags:
        VkShaderStageFlag.vertexBit
      | VkShaderStageFlag.fragmentBit
    , pImmutableSamplers: null
    };

    bindings[1] = binding;
  }

  { // -- material sampler
    VkDescriptorSetLayoutBinding binding = {
      binding:            2
    , descriptorType:     VkDescriptorType.combinedImageSampler
    , descriptorCount:    cast(uint32_t)rs.textureSampler.length
    , stageFlags:         VkShaderStageFlag.fragmentBit
    , pImmutableSamplers: null // TODO null? really?
    };

    bindings[2] = binding;
  }

  { // -- create descriptor set layout
    VkDescriptorSetLayoutCreateInfo info = {
      sType:        VkStructureType.descriptorSetLayoutCreateInfo
    , pNext:        null
    , flags:        0
    , bindingCount: cast(uint32_t)bindings.length
    , pBindings:    bindings.ptr
    };

    fw.device
      .vkCreateDescriptorSetLayout(&info, null, &rs.descriptorSetLayout)
      .EnforceVk;
  }
}

////////////////////////////////////////////////////////////////////////////////
void CreateGraphicsPipeline(
  ref Rasterizer rs
, ref Framework fw
, VkExtent2D framebufferSize
) {
  rs.framebufferSize = framebufferSize;

  import vkshader;

  VkShaderModule vertShaderModule =
    fw.LoadShaderModule("shaders/genericRasterizer.vert");
  VkShaderModule fragShaderModule =
    fw.LoadShaderModule("shaders/genericRasterizer.frag");

  VkPipelineShaderStageCreateInfo vertShaderStageInfo = {
      sType: VkStructureType.pipelineShaderStageCreateInfo
    , pNext: null
    , flags: 0
    , stage: VkShaderStageFlag.vertexBit
    , module_: vertShaderModule
    , pName: "main"
    , pSpecializationInfo: null
  };

  VkPipelineShaderStageCreateInfo fragShaderStageInfo = {
      sType: VkStructureType.pipelineShaderStageCreateInfo
    , pNext: null
    , flags: 0
    , stage: VkShaderStageFlag.fragmentBit
    , module_: fragShaderModule
    , pName: "main"
    , pSpecializationInfo: null
  };

  auto shaderStages = Array!(VkPipelineShaderStageCreateInfo)(2);
  shaderStages[0] = vertShaderStageInfo;
  shaderStages[1] = fragShaderStageInfo;

  auto bindingDescription   = Vertex.GetBindingDescription;
  auto attributeDescription = Vertex.GetAttributBindingDescriptions;

  VkPipelineVertexInputStateCreateInfo vertexInput = {
    sType: VkStructureType.pipelineVertexInputStateCreateInfo
  , pNext: null
  , flags: 0
  , vertexBindingDescriptionCount: 1
  , pVertexBindingDescriptions: &bindingDescription
  , vertexAttributeDescriptionCount: cast(uint32_t)attributeDescription.length
  , pVertexAttributeDescriptions: attributeDescription.ptr
  };

  VkPipelineInputAssemblyStateCreateInfo inputAssembly = {
    sType: VkStructureType.pipelineInputAssemblyStateCreateInfo
  , pNext: null
  , flags: 0
  , topology: VkPrimitiveTopology.triangleList
  , primitiveRestartEnable: VK_FALSE
  };

  VkViewport viewport = {
    x:        0.0f
  , y:        0.0f
  , width:    800
  , height:   600
  , minDepth: 0.0f
  , maxDepth: 1.0f
  };

  VkRect2D scissor = {
    offset: VkOffset2D(0, 0)
  , extent: VkExtent2D(800, 600)
  };

  VkPipelineViewportStateCreateInfo viewportState = {
    sType: VkStructureType.pipelineViewportStateCreateInfo
  , pNext: null
  , flags: 0
  , viewportCount: 1
  , pViewports: &viewport
  , scissorCount: 1
  , pScissors: &scissor
  };

  VkPipelineRasterizationStateCreateInfo rasterizer = {
    sType: VkStructureType.pipelineRasterizationStateCreateInfo
  , pNext: null
  , flags: 0
  , depthClampEnable: VK_FALSE
  , rasterizerDiscardEnable: VK_FALSE
  , polygonMode: VkPolygonMode.fill
  , cullMode: VkCullModeFlag.backBit
  , frontFace: VkFrontFace.clockwise
  , depthBiasEnable: VK_FALSE
  , depthBiasConstantFactor: 0.0f
  , depthBiasClamp: 0.0f
  , depthBiasSlopeFactor: 0.0f
  , lineWidth: 1.0f
  };

  VkPipelineMultisampleStateCreateInfo multisample = {
    sType: VkStructureType.pipelineMultisampleStateCreateInfo
  , pNext: null
  , flags: 0
  , rasterizationSamples: VkSampleCountFlag.i1Bit
  , sampleShadingEnable: VK_FALSE
  , minSampleShading: 0.0f
  , pSampleMask: null
  , alphaToCoverageEnable: VK_FALSE
  , alphaToOneEnable: VK_FALSE
  };

  VkPipelineColorBlendAttachmentState colorBlendAttachment = {
    blendEnable: VK_FALSE
  , srcColorBlendFactor: VkBlendFactor.one // FIXME might be zero
  , dstColorBlendFactor: VkBlendFactor.one // might be zero
  , colorBlendOp: VkBlendOp.add
  , srcAlphaBlendFactor: VkBlendFactor.one // FIXME might be zero
  , dstAlphaBlendFactor: VkBlendFactor.one // FIXME might be zero
  , alphaBlendOp: VkBlendOp.add
  , colorWriteMask:
      VkColorComponentFlag.rBit | VkColorComponentFlag.gBit
    | VkColorComponentFlag.bBit | VkColorComponentFlag.aBit
  };

  VkPipelineColorBlendStateCreateInfo colorBlend = {
    sType: VkStructureType.pipelineColorBlendStateCreateInfo
  , pNext: null
  , flags: 0
  , logicOpEnable: VK_FALSE
  , logicOp: VkLogicOp.copy
  , attachmentCount: 1
  , pAttachments: &colorBlendAttachment
  , blendConstants: [0.0f, 0.0f, 0.0f, 0.0f]
  };

  VkPipelineDepthStencilStateCreateInfo depthStencil = {
    sType: VkStructureType.pipelineDepthStencilStateCreateInfo
  , pNext: null
  , flags: 0
  , depthTestEnable: VK_TRUE
  , depthWriteEnable: VK_TRUE
  , depthCompareOp: VkCompareOp.less
  , depthBoundsTestEnable: VK_FALSE
  , stencilTestEnable: VK_FALSE
  , front: VkStencilOpState()
  , back:  VkStencilOpState()
  , minDepthBounds: 0.0f
  , maxDepthBounds: 1.0f
  };

  VkPipelineLayoutCreateInfo pipelineLayoutInfo = {
    sType:                  VkStructureType.pipelineLayoutCreateInfo
  , pNext:                  null
  , flags:                  0
  , setLayoutCount:         1
  , pSetLayouts:            &rs.descriptorSetLayout
  , pushConstantRangeCount: 0
  , pPushConstantRanges:    null
  };

  fw.device
    .vkCreatePipelineLayout(&pipelineLayoutInfo, null, &rs.pipelineLayout)
    .EnforceVk;

  { // -- create graphics pipeline
    VkGraphicsPipelineCreateInfo info = {
      sType: VkStructureType.graphicsPipelineCreateInfo
    , pNext: null
    , flags: 0
    , stageCount: 2
    , pStages: shaderStages.ptr
    , pVertexInputState: &vertexInput
    , pInputAssemblyState: &inputAssembly
    , pTessellationState: null
    , pViewportState: &viewportState
    , pRasterizationState: &rasterizer
    , pMultisampleState: &multisample
    , pDepthStencilState: &depthStencil
    , pColorBlendState: &colorBlend
    , pDynamicState: null
    , layout: rs.pipelineLayout
    , renderPass: fw.renderPass
    , subpass: 0
    , basePipelineHandle: null
    , basePipelineIndex: 0
    };

    if (rs.graphicsPipeline)
      fw.device.vkDestroyPipeline(rs.graphicsPipeline, null);

    fw.device
      .vkCreateGraphicsPipelines(
        null
      , 1
      , &info
      , null
      , &rs.graphicsPipeline
      ).EnforceVk;
  }

  fw.device.vkDestroyShaderModule(fragShaderModule, null);
  fw.device.vkDestroyShaderModule(vertShaderModule, null);
}

////////////////////////////////////////////////////////////////////////////////
void LoadModel(ref Rasterizer rs, ref Framework fw, const string filename) {
  // OBJ LOADER? WTF? AHH

  rs.indices = 0;
  rs.vertices = 0;
  // rs.CreateVertexBuffer(fw, );
  // rs.CreateIndexBuffer(fw, );
  // rs.CreateMaterialBuffer(fw, );
  // rs.CreateTextureImages(fw, );
}

////////////////////////////////////////////////////////////////////////////////
void CreateMaterialBuffer(
  ref Rasterizer rs
, ref Framework fw
, inout ref Array!MatrialObj materials
) {
   { // -- create material buffer
    VkBufferCreateInfo info = {
      sType: VkStructureType.bufferCreateInfo
    , pNext: null
    , flags: 0
    , size: materials.size
    , usage: VkBufferUsageFlag.storageBufferBit
    , sharingMode: VkSharingMode.exclusive
    , queueFamilyIndexCount: 0
    , pQueueFamilyIndices: null
    };

    fw.CreateBuffer(
      info
    , VkMemoryPropertyFlag.hostVisibleBit | VkMemoryPropertyFlag.hostCoherentBit
    , &rs.matColorBuffer
    , &rs.matColorBufferMemory
    );
  }

  void * data;
  fw.device.vkMapMemory(rs.matColorBufferMemory, 0, materials.size, 0, &data);
  memcpy(data, materials.ptr, materials.size);
  fw.device.vkUnmapMemory(rs.matColorBufferMemory);
}

////////////////////////////////////////////////////////////////////////////////
void CreateVertexBuffer(
  ref Rasterizer rs
, ref Framework fw
, inout ref Array!Vertex vertices
) {
  VkBuffer stagingBuffer;
  VkDeviceMemory stagingBufferMemory;

  { // -- create staging buffer
    VkBufferCreateInfo info = {
      sType: VkStructureType.bufferCreateInfo
    , pNext: null
    , flags: 0
    , size: vertices.size
    , usage: VkBufferUsageFlag.transferSrcBit
    , sharingMode: VkSharingMode.exclusive
    , queueFamilyIndexCount: 0
    , pQueueFamilyIndices: null
    };

    fw.CreateBuffer(
      info
    , VkMemoryPropertyFlag.hostVisibleBit | VkMemoryPropertyFlag.hostCoherentBit
    , &stagingBuffer
    , &stagingBufferMemory
    );
  }

  void * data;
  fw.device.vkMapMemory(stagingBufferMemory, 0, vertices.size, 0, &data);
  memcpy(data, vertices.ptr, cast(size_t)vertices.size);
  fw.device.vkUnmapMemory(stagingBufferMemory);

  { // -- create vertex buffer
    VkBufferCreateInfo info = {
      sType: VkStructureType.bufferCreateInfo
    , pNext: null
    , flags: 0
    , size: vertices.size
    , usage:
        VkBufferUsageFlag.transferDstBit | VkBufferUsageFlag.vertexBufferBit
    , sharingMode: VkSharingMode.exclusive
    , queueFamilyIndexCount: 0
    , pQueueFamilyIndices: null
    };

    fw.CreateBuffer(
      info
    , VkMemoryPropertyFlag.deviceLocalBit
    , &rs.vertexBuffer
    , &rs.vertexBufferMemory
    );
  }

  { // -- copy buffer
    auto cmdBuffer = ScopedSingleTimeCommandBuffer(fw);
    scope(exit) cmdBuffer.End;

    VkBufferCopy copyRegion = {
      srcOffset: 0
    , dstOffset: 0
    , size:      cast(size_t)vertices.size
    };

    cmdBuffer.cmdBuffer
      .vkCmdCopyBuffer(
        stagingBuffer
      , rs.vertexBuffer
      , cast(uint32_t)vertices.size
      , &copyRegion
      );
  }
}

////////////////////////////////////////////////////////////////////////////////
void CreateIndexBuffer(
  ref Rasterizer rs
, ref Framework fw
, inout ref Array!(uint32_t) indices
) {
  VkBuffer stagingBuffer;
  VkDeviceMemory stagingBufferMemory;

  { // -- create staging buffer
    VkBufferCreateInfo info = {
      sType: VkStructureType.bufferCreateInfo
    , pNext: null
    , flags: 0
    , size: indices.size
    , usage: VkBufferUsageFlag.transferSrcBit
    , sharingMode: VkSharingMode.exclusive
    , queueFamilyIndexCount: 0
    , pQueueFamilyIndices: null
    };

    fw.CreateBuffer(
      info
    , VkMemoryPropertyFlag.hostVisibleBit | VkMemoryPropertyFlag.hostCoherentBit
    , &stagingBuffer
    , &stagingBufferMemory
    );
  }

  void * data;
  fw.device.vkMapMemory(stagingBufferMemory, 0, indices.size, 0, &data);
  memcpy(data, indices.ptr, cast(size_t)indices.size);
  fw.device.vkUnmapMemory(stagingBufferMemory);

  { // -- create index buffer
    VkBufferCreateInfo info = {
      sType: VkStructureType.bufferCreateInfo
    , pNext: null
    , flags: 0
    , size: indices.size
    , usage: VkBufferUsageFlag.transferDstBit | VkBufferUsageFlag.indexBufferBit
    , sharingMode: VkSharingMode.exclusive
    , queueFamilyIndexCount: 0
    , pQueueFamilyIndices: null
    };

    fw.CreateBuffer(
      info
    , VkMemoryPropertyFlag.deviceLocalBit
    , &rs.indexBuffer
    , &rs.indexBufferMemory
    );
  }

  { // -- copy buffer
    auto cmdBuffer = ScopedSingleTimeCommandBuffer(fw);
    scope(exit) cmdBuffer.End;

    VkBufferCopy copyRegion = {
      srcOffset: 0
    , dstOffset: 0
    , size:      cast(size_t)indices.size
    };

    cmdBuffer.cmdBuffer
      .vkCmdCopyBuffer(
        stagingBuffer
      , rs.indexBuffer
      , cast(uint32_t)indices.size
      , &copyRegion
      );
  }

  // -- free staging buffer
  fw.device.vkDestroyBuffer(stagingBuffer, null);
  fw.device.vkFreeMemory(stagingBufferMemory, null);
}

////////////////////////////////////////////////////////////////////////////////
void UpdateDescriptorSet(ref Rasterizer rs, ref Framework fw) {
  { // -- allocate descriptor set
    VkDescriptorSetLayout[1] layouts = [ rs.descriptorSetLayout ];
    VkDescriptorSetAllocateInfo info = {
       sType:              VkStructureType.descriptorSetAllocateInfo
    ,  pNext:              null
    ,  descriptorPool:     fw.descriptorPool
    ,  descriptorSetCount: cast(uint32_t)layouts.length
    ,  pSetLayouts:        layouts.ptr
    };

    fw.device
      .vkAllocateDescriptorSets(&info, &rs.descriptorSet)
      .EnforceVk;
  }

  VkDescriptorBufferInfo bufferInfo = {
    buffer: rs.uniformBuffer
  , offset: 0
  , range: VK_WHOLE_SIZE
  };

  VkDescriptorBufferInfo materialColorBufferInfo = {
    buffer: rs.matColorBuffer
  , offset: 0
  , range:  VK_WHOLE_SIZE
  };

  auto descriptorWrites = Array!(VkWriteDescriptorSet)(3);
  VkWriteDescriptorSet descriptorWriteSet = {
    sType: VkStructureType.writeDescriptorSet
  , pNext: null
  , dstSet: rs.descriptorSet
  , dstBinding: 0
  , dstArrayElement: 0
  , descriptorCount: 1
  , descriptorType: VkDescriptorType.beginRange // fill later
  , pImageInfo: null
  , pBufferInfo: null
  , pTexelBufferView: null
  };

  { // -- matrices
    descriptorWriteSet.descriptorType = VkDescriptorType.uniformBuffer;
    descriptorWriteSet.dstBinding = 0;
    descriptorWriteSet.pBufferInfo = &bufferInfo;

    descriptorWrites[0] = descriptorWriteSet;
  }

  { // -- materials
    descriptorWriteSet.descriptorType = VkDescriptorType.storageBuffer;
    descriptorWriteSet.dstBinding = 1;
    descriptorWriteSet.pBufferInfo = &materialColorBufferInfo;
    descriptorWrites[1] = descriptorWriteSet;
  }

  { // -- textures

    auto imageInfo =
      Array!(VkDescriptorImageInfo)(rs.textureSampler.length);

    foreach (i; 0 .. imageInfo.length) {
      VkDescriptorImageInfo info = {
        sampler:     rs.textureSampler[i]
      , imageView:   rs.textureImageView[i]
      , imageLayout: VkImageLayout.shaderReadOnlyOptimal
      };

      imageInfo[i] = info;
    }

    descriptorWriteSet.descriptorType = VkDescriptorType.combinedImageSampler;
    descriptorWriteSet.dstBinding = 2;
    descriptorWriteSet.descriptorCount = cast(uint32_t)imageInfo.length;
    descriptorWriteSet.pImageInfo = imageInfo.ptr;
    descriptorWriteSet.pBufferInfo = null;

    descriptorWrites[2] = descriptorWriteSet;
  }

  fw.device
    .vkUpdateDescriptorSets(
      cast(uint32_t)descriptorWrites.length
    , descriptorWrites.ptr
    , 0
    , null
    );
}

////////////////////////////////////////////////////////////////////////////////
void CreateUniformBuffer(ref Rasterizer rs, ref Framework fw) {
  VkDeviceSize bufferSize = UniformBufferObject.sizeof;

  VkBufferCreateInfo info = {
    sType: VkStructureType.bufferCreateInfo
  , pNext: null
  , flags: 0
  , size: bufferSize
  , usage: VkBufferUsageFlag.uniformBufferBit
  , sharingMode: VkSharingMode.exclusive
  , queueFamilyIndexCount: 0
  , pQueueFamilyIndices: null
  };

  fw.CreateBuffer(
    info
  , VkMemoryPropertyFlag.hostVisibleBit
  | VkMemoryPropertyFlag.hostCoherentBit
  , &rs.uniformBuffer
  , &rs.uniformBufferMemory
  );
}

////////////////////////////////////////////////////////////////////////////////
void CreateTextureImages(
  ref Rasterizer rs
, ref Framework fw
, ref Array!(string) textures
) {

  import imago;

  rs.textureImage.length       = textures.length;
  rs.textureImageMemory.length = textures.length;
  rs.textureImageView.length   = textures.length;
  rs.textureSampler.length     = textures.length;

  foreach (it; 0 .. textures.length) {
    string filename = textures[it];

    int width, height;
    ubyte * pixels = cast(ubyte*)
      img_load_pixels(
        cast(char*)filename.ptr
      , &width, &height
      , img_fmt.IMG_FMT_RGBA32
      );
    scope(exit) img_free_pixels(pixels);

    VkDeviceSize imageSize = width*height*4;

    // -- stage buffer
    VkBuffer stagingBuffer;
    VkDeviceMemory stagingBufferMemory;

    VkBufferCreateInfo info = {
      sType: VkStructureType.bufferCreateInfo
    , pNext: null
    , flags: 0
    , size: imageSize
    , usage: VkBufferUsageFlag.transferSrcBit
    , sharingMode: VkSharingMode.exclusive
    , queueFamilyIndexCount: 0
    , pQueueFamilyIndices: null
    };

    fw.CreateBuffer(
      info
    , VkMemoryPropertyFlag.hostVisibleBit
    | VkMemoryPropertyFlag.hostCoherentBit
    , &stagingBuffer
    , &stagingBufferMemory
    );

    void * data;
    fw.device.vkMapMemory(stagingBufferMemory, 0, imageSize, 0, &data);
    memcpy(data, pixels, cast(uint32_t)imageSize);
    fw.device.vkUnmapMemory(stagingBufferMemory);

    Image image =
      fw.CreateImage(
        VkImageType.i2D
      , VkFormat.r8g8b8a8Unorm
      , VkExtent3D(width, height, 1)
      , VkImageTiling.optimal
      , VkImageUsageFlag.transferSrcBit | VkImageUsageFlag.sampledBit
      , VkMemoryPropertyFlag.deviceLocalBit
      );

    // -- stage buffer up to image
    {
      fw.TransitionImageLayout(
        image
      , VkFormat.r8g8b8a8Unorm
      , VkImageLayout.undefined
      , VkImageLayout.transferDstOptimal
      );

      fw.CopyBufferToImage(image, stagingBuffer, width, height);

      fw.TransitionImageLayout(
        image
      , VkFormat.r8g8b8a8Unorm
      , VkImageLayout.transferDstOptimal
      , VkImageLayout.shaderReadOnlyOptimal
      );
    }

    fw.device.vkDestroyBuffer(stagingBuffer, null);
    fw.device.vkFreeMemory(stagingBufferMemory, null);

    rs.textureImage[it] = image.image;
    rs.textureImageMemory[it] = image.memory;
    { // -- create texture image view
      VkImageSubresourceRange subresourceRange = {
        aspectMask:     VkImageAspectFlag.colorBit
      , baseMipLevel:   0
      , levelCount:     1
      , baseArrayLayer: 0
      , layerCount:     1
      };

      fw.CreateImageView(
        image
      , VkImageViewType.i2D
      , VkFormat.r8g8b8a8Unorm
      , subresourceRange
      );

      rs.textureImageView[it] = image.imageView;
    }
    rs.textureSampler[it] = rs.CreateTextureSampler(fw);
  }
}

////////////////////////////////////////////////////////////////////////////////
VkSampler CreateTextureSampler(ref Rasterizer rs, ref Framework fw) {
  VkSamplerCreateInfo info = {
    sType:                   VkStructureType.samplerCreateInfo
  , pNext:                   null
  , flags:                   0
  , magFilter:               VkFilter.linear
  , minFilter:               VkFilter.linear
  , mipmapMode:              VkSamplerMipmapMode.linear
  , addressModeU:            VkSamplerAddressMode.repeat
  , addressModeV:            VkSamplerAddressMode.repeat
  , addressModeW:            VkSamplerAddressMode.repeat
  , mipLodBias:              0.0f
  , anisotropyEnable:        VK_TRUE
  , maxAnisotropy:           16
  , compareEnable:           VK_FALSE
  , compareOp:               VkCompareOp.always
  , minLod:                  0.0f
  , maxLod:                  0.0f
  , borderColor:             VkBorderColor.intOpaqueBlack
  , unnormalizedCoordinates: VK_FALSE
  };

  VkSampler textureSampler;

  fw.device
    .vkCreateSampler(&info, null, &textureSampler)
    .EnforceVk;

  return textureSampler;
}

////////////////////////////////////////////////////////////////////////////////
void UpdateUniformBuffer(ref Framework fw, ref Rasterizer rs) {
  UniformBufferObject ubo;
  ubo.model = [
    1.0f, 0.0f, 0.0f, 0.0f,
    0.0f, 1.0f, 0.0f, 0.0f,
    0.0f, 0.0f, 1.0f, 0.0f,
    0.0f, 0.0f, 0.0f, 1.0f
  ];

  ubo.view = [
    1.0f, 0.0f, 0.0f, 0.0f,
    0.0f, 1.0f, 0.0f, 0.0f,
    0.0f, 0.0f, 1.0f, 0.0f,
    0.0f, 0.0f, 0.0f, 1.0f
  ];

  const float aspectRatio = 1.0f;

  ubo.projection = [
    1.0f, 0.0f, 0.0f, 0.0f,
    0.0f, 1.0f, 0.0f, 0.0f,
    0.0f, 0.0f, 1.0f, 0.0f,
    0.0f, 0.0f, 0.0f, 1.0f
  ];
  ubo.projection[5] *= -1.0f;

  void* data;
  // TODO I don't think we can really do this easily.., mapping a struct of
  //   arrays
  vkMapMemory(
    fw.device
  , rs.uniformBufferMemory
  , 0
  , ubo.sizeof
  , 0
  , &data
  );

  memcpy(data, &ubo, ubo.sizeof);

  vkUnmapMemory(fw.device, rs.uniformBufferMemory);
}
