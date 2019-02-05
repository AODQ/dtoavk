module vkcontext;

import core.stdc.stdint;
import core.stdc.stdio;

import neobc.array;
import neobc.range;

import glfw;
import vkimage;
import utility;
import vk;

////////////////////////////////////////////////////////////////////////////////
enum ImguiMaxPossibleBackBuffers = 16;
enum ImguiVkQueuedFrames = 2;

////////////////////////////////////////////////////////////////////////////////
struct ApplicationSettings {
  string name;
  uint32_t    windowResolutionX;
  uint32_t    windowResolutionY;
  VkFormat    surfaceFormat;
  bool        enableValidation;
  bool        enableVSync;
};

////////////////////////////////////////////////////////////////////////////////
struct Framework {
  this(ApplicationSettings applicationSettings_) {
    applicationSettings = applicationSettings_;

    backBuffers     = Array!(VkImage)(ImguiMaxPossibleBackBuffers);
    backBufferViews = Array!(VkImageView)(ImguiMaxPossibleBackBuffers);
    frameBuffers    = Array!(VkFramebuffer)(ImguiMaxPossibleBackBuffers);
  }

  @disable this();

  ApplicationSettings applicationSettings;
  GLFWwindow* window;

  VkRenderPass renderPass;

  uint32_t           computeQueueFamilyIndex;
  VkQueue            computeQueue;
  VkDevice           device;
  uint32_t           graphicsQueueFamilyIndex;
  VkQueue            graphicsQueue;
  VkInstance         instance;
  VkPhysicalDevice   physicalDevice;
  VkDescriptorPool descriptorPool;
  VkSemaphore  [ImguiVkQueuedFrames] semaphoreImagesAcquired;
  VkSemaphore  [ImguiVkQueuedFrames] semaphoreRendersFinished;
  VkCommandPool[ImguiVkQueuedFrames] commandPools;
  VkSurfaceFormatKHR surfaceFormat;
  VkSurfaceKHR       surface;
  uint32_t           transferQueueFamilyIndex;
  VkQueue            transferQueue;
  VkSwapchainKHR swapchain;

  VkPipelineCache pipelineCache = null;

  VkPhysicalDeviceMemoryProperties physicalDeviceMemoryProperties;

  uint32_t frameIndex;

   // keep track of recently rendered swapchain
  uint32_t[ImguiVkQueuedFrames] backBufferIndices;

  Array!(VkImage)       backBuffers;
  Array!(VkImageView)   backBufferViews;
  Array!(VkFramebuffer) frameBuffers;

  Image depthImage;

  VkCommandBuffer[ImguiVkQueuedFrames] commandBuffers;
  VkFence[ImguiVkQueuedFrames] fenceFrame;

  VkCommandBuffer RCommandBuffer() { return commandBuffers[frameIndex]; }

  VkPhysicalDeviceRayTracingPropertiesNV raytracingProperties;
}

////////////////////////////////////////////////////////////////////////////////
void CreateDescriptorPool (ref Framework fw) {
  auto poolSizes = Array!(VkDescriptorPoolSize)(3);
  poolSizes[0] = VkDescriptorPoolSize(VkDescriptorType.combinedImageSampler, 1);
  poolSizes[1] = VkDescriptorPoolSize(VkDescriptorType.uniformBuffer,        1);
  poolSizes[2] = VkDescriptorPoolSize(VkDescriptorType.storageBuffer,        1);

  VkDescriptorPoolCreateInfo info = {
    sType: VkStructureType.descriptorPoolCreateInfo
  , pNext: null
  , flags: VkDescriptorPoolCreateFlag.freeDescriptorSetBit
  , maxSets: 1000
  , poolSizeCount: cast(uint32_t)poolSizes.length
  , pPoolSizes: poolSizes.ptr
  };

  fw.device
    .vkCreateDescriptorPool(
      &info
    , null
    , &fw.descriptorPool
    ).EnforceVk;
}

////////////////////////////////////////////////////////////////////////////////
void CreateFrameBuffer(ref Framework fw) {
  auto attachments = Array!(VkImageView)(2);
  attachments[0] = fw.backBufferViews[0];
  attachments[1] = fw.depthImage.imageView;

  VkFramebufferCreateInfo info = {
    sType: VkStructureType.framebufferCreateInfo
  , pNext: null
  , flags: 0
  , renderPass: fw.renderPass
  , attachmentCount: cast(uint32_t)(attachments.length)
  , pAttachments: attachments.ptr
  , width: 800
  , height: 600
  , layers: 1
  };

  foreach (i; 0 .. fw.backBuffers.length) {
    attachments[0] = fw.backBufferViews[i];
    fw.device.vkCreateFramebuffer(&info, null, &fw.frameBuffers[i]);
  }
}

////////////////////////////////////////////////////////////////////////////////
void CreateSwapchainImageViews(ref Framework fw) {
  VkImageSubresourceRange subresourceRange = {
    aspectMask:     VkImageAspectFlag.colorBit
  , baseMipLevel:   0
  , levelCount:     1
  , baseArrayLayer: 0
  , layerCount:     1
  };

  VkImageViewCreateInfo info = {
    sType: VkStructureType.imageViewCreateInfo
  , pNext: null
  , flags: 0
  , image: null
  , viewType: VkImageViewType.i2D
  , format: fw.surfaceFormat.format
  , components:
      VkComponentMapping(
        VkComponentSwizzle.r
      , VkComponentSwizzle.g
      , VkComponentSwizzle.b
      , VkComponentSwizzle.a
      )
  , subresourceRange: subresourceRange
  };

  // resize
  fw.backBufferViews = Array!(VkImageView)(fw.backBuffers.length);

  // create image views, assign info.image for each image view
  foreach (it; 0 .. fw.backBufferViews.length) {
    info.image = fw.backBuffers[it];
    fw.device
      .vkCreateImageView(&info, null, &fw.backBufferViews[it])
      .EnforceVk;
  }
}

////////////////////////////////////////////////////////////////////////////////
void CreateRenderPass(ref Framework fw)
{
  VkAttachmentDescription colorAttachment = {
    flags:          0
  , format:         fw.surfaceFormat.format
  , samples:        VkSampleCountFlag.i1Bit
  , loadOp:         VkAttachmentLoadOp.clear
  , storeOp:        VkAttachmentStoreOp.store
  , stencilLoadOp:  VkAttachmentLoadOp.dontCare
  , stencilStoreOp: VkAttachmentStoreOp.dontCare
  , initialLayout:  VkImageLayout.undefined
  , finalLayout:    VkImageLayout.presentSrcKhr
  };

  VkAttachmentReference colorAttachmentReference = {
    attachment: 0
  , layout: VkImageLayout.colorAttachmentOptimal
  };

  VkAttachmentDescription depthAttachment = {
    format:         VkFormat.d32Sfloat // TODO use FindDepthFormat
  , samples:        VkSampleCountFlag.i1Bit
  , loadOp:         VkAttachmentLoadOp.clear
  , storeOp:        VkAttachmentStoreOp.dontCare
  , stencilLoadOp:  VkAttachmentLoadOp.dontCare
  , stencilStoreOp: VkAttachmentStoreOp.dontCare
  , initialLayout:  VkImageLayout.undefined
  , finalLayout:    VkImageLayout.depthStencilAttachmentOptimal
  };

  VkAttachmentReference depthAttachmentReference = {
    attachment: 1
  , layout: VkImageLayout.depthStencilAttachmentOptimal
  };

  VkSubpassDescription subpassDescription = {
    flags:                   0
  , pipelineBindPoint:       VkPipelineBindPoint.graphics
  , inputAttachmentCount:    0
  , pInputAttachments:       null
  , colorAttachmentCount:    1
  , pColorAttachments:       &colorAttachmentReference
  , pResolveAttachments:     null
  , pDepthStencilAttachment: &depthAttachmentReference
  , preserveAttachmentCount: 0
  , pPreserveAttachments:    null
  };

  VkSubpassDependency subpassDependency = {
    srcSubpass: VK_SUBPASS_EXTERNAL
  , dstSubpass: 0
  , srcStageMask: VkPipelineStageFlag.colorAttachmentOutputBit
  , dstStageMask: VkPipelineStageFlag.colorAttachmentOutputBit
  , srcAccessMask: 0
  , dstAccessMask: VkAccessFlag.colorAttachmentWriteBit
  };

  auto attachmentDescriptions = Array!(VkAttachmentDescription)(2);
  attachmentDescriptions[0] = colorAttachment;
  attachmentDescriptions[1] = depthAttachment;

  VkRenderPassCreateInfo renderPassInfo = {
    sType: VkStructureType.renderPassCreateInfo
  , pNext: null
  , flags: 0
  , attachmentCount: cast(uint32_t)(attachmentDescriptions.length)
  , pAttachments: attachmentDescriptions.ptr
  , subpassCount: 1
  , pSubpasses: &subpassDescription
  , dependencyCount: 1
  , pDependencies: &subpassDependency
  };

  fw.device
    .vkCreateRenderPass(
      &renderPassInfo
    , null
    , &fw.renderPass
    ).EnforceVk;
}

////////////////////////////////////////////////////////////////////////////////
Array!(T) GetVkArray(string fnName, bool hasEnforce, T, U...)(ref U params) {
  uint32_t arrayLength;

  // TODO ; use format when BetterC allows it
  mixin(
    (hasEnforce?`EnforceVk(`:`(`)
  ~ fnName
  ~ `(params, &arrayLength, null));`);
  auto array = Array!(T)(arrayLength);
  mixin(
    (hasEnforce?`EnforceVk(`:`(`)
  ~ fnName
  ~ `(params, &arrayLength, array.ptr));`);

  return array;
}

////////////////////////////////////////////////////////////////////////////////
void CreateSwapchain(ref Framework fw) {
  VkSwapchainKHR oldSwapchain = fw.swapchain;

  VkSurfaceCapabilitiesKHR capabilities;
  fw.physicalDevice
    .vkGetPhysicalDeviceSurfaceCapabilitiesKHR(fw.surface, &capabilities)
    .EnforceVk;

  VkSwapchainCreateInfoKHR info = {
    sType:                 VkStructureType.swapchainCreateInfoKhr
  , pNext:                 null
  , flags:                 0
  , surface:               fw.surface
  , minImageCount:         capabilities.minImageCount
  , imageFormat:           fw.surfaceFormat.format
  , imageColorSpace:       fw.surfaceFormat.colorSpace
  , imageExtent:           VkExtent2D (
      800
    , 600
    )
  , imageArrayLayers:      1
  , imageUsage:
      VkImageUsageFlag.colorAttachmentBit
    // | VkImageUsageFlag.transferDstBit
  , imageSharingMode:      VkSharingMode.exclusive
  , queueFamilyIndexCount: 0
  , pQueueFamilyIndices:   null
  , preTransform:          VkSurfaceTransformFlagKHR.identityBitKhr
  , compositeAlpha:        VkCompositeAlphaFlagKHR.opaqueBitKhr
  , presentMode:           VkPresentModeKHR.immediateKhr
  , clipped:               VK_TRUE
  , oldSwapchain:          fw.swapchain
  };

  // -- create swapchain
  fw.device
    .vkCreateSwapchainKHR(&info, null, &fw.swapchain)
    .EnforceVk;

  if (oldSwapchain) {
    foreach (ref imageView; fw.backBufferViews.AsRange) {
      vkDestroyImageView(fw.device, imageView, null);
      imageView = null;
    }
    vkDestroySwapchainKHR(fw.device, oldSwapchain, null);
  }

  // -- create image for each backbuffer
  fw.backBuffers = fw.device.vkGetSwapchainImagesKHRNeo(fw.swapchain);
}

////////////////////////////////////////////////////////////////////////////////
void CreateCommandBuffers(ref Framework fw) {
  foreach (cmdBufferIdx; 0 .. ImguiVkQueuedFrames) {
    { // -- reset command buffer
      VkCommandPoolCreateInfo info = {
        sType: VkStructureType.commandPoolCreateInfo
      , flags: VkCommandPoolCreateFlag.resetCommandBufferBit
      , queueFamilyIndex: fw.graphicsQueueFamilyIndex
      };

      fw.device
        .vkCreateCommandPool(
          &info
        , null
        , &fw.commandPools[cmdBufferIdx]
        ).EnforceVk;
    }

    { // -- allocate buffer
      VkCommandBufferAllocateInfo info = {
        sType:              VkStructureType.commandBufferAllocateInfo
      , pNext:              null
      , commandPool:        fw.commandPools[cmdBufferIdx]
      , level:              VkCommandBufferLevel.primary
      , commandBufferCount: 1
      };

      fw.device
        .vkAllocateCommandBuffers(&info , &fw.commandBuffers[cmdBufferIdx])
        .EnforceVk;
    }

    { // -- fence for frame
      VkFenceCreateInfo info = {
        sType: VkStructureType.fenceCreateInfo
      , pNext: null
      , flags: VkFenceCreateFlag.signaledBit
      };

      fw.device
        .vkCreateFence(&info, null, &fw.fenceFrame[cmdBufferIdx]);
    }

    { // -- semaphore for image acquisition and render finish
      VkSemaphoreCreateInfo info = {
        sType: VkStructureType.semaphoreCreateInfo
      , pNext: null
      , flags: 0
      };

      fw.device
        .vkCreateSemaphore(
          &info
        , null
        , &fw.semaphoreImagesAcquired[cmdBufferIdx]
        );

      fw.device
        .vkCreateSemaphore(
          &info
        , null
        , &fw.semaphoreRendersFinished[cmdBufferIdx]
      );
    }

    fw.physicalDevice
      .vkGetPhysicalDeviceMemoryProperties(
        &fw.physicalDeviceMemoryProperties
      );

  }
}


////////////////////////////////////////////////////////////////////////////////
void InitializeWindow (ref Framework fw) {
  glfwInit.EnforceAssert;
  glfwVulkanSupported.EnforceAssert;

  glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
  glfwWindowHint(GLFW_RESIZABLE,  GLFW_FALSE);
  glfwWindowHint(GLFW_FLOATING,   GLFW_TRUE);

  fw.window =
    glfwCreateWindow(
      cast(int)fw.applicationSettings.windowResolutionX
    , cast(int)fw.applicationSettings.windowResolutionY
    , cast(const(char*))fw.applicationSettings.name
    , null
    , null
    );
  fw.window.EnforceAssert;
}

////////////////////////////////////////////////////////////////////////////////
void InitializeVulkan(ref Framework fw) {
  VkApplicationInfo applicationInfo = {
    sType:              VkStructureType.applicationInfo
  , pNext:              null
  , pApplicationName:   fw.applicationSettings.name.ptr
  , applicationVersion: VK_MAKE_VERSION(0, 0, 1)
  , pEngineName:        "dtoavk"
  , engineVersion:      VK_MAKE_VERSION(0, 0, 1)
  , apiVersion:         VK_API_VERSION_1_1
  };

  // -- get extensions
  Array!(const(char)*) instanceExtensions;
  GetRequiredGlfwExtensions(instanceExtensions);

  // -- get layers
  Array!(const(char)*) instanceLayers;

  // -- validation
  if (fw.applicationSettings.enableValidation) {
    instanceExtensions ~= VK_EXT_DEBUG_REPORT_EXTENSION_NAME;
    instanceLayers ~= "VK_LAYER_LUNARG_standard_validation";
  }

  // -- create instance

  printf("InstanceExtensions:\n");
  foreach ( ref i; instanceExtensions.AsRange )
    printf(" * %s\n", i);
  printf("---\n");
  printf("InstanceLayers:\n");
  foreach ( ref i; instanceLayers.AsRange )
    printf(" * %s\n", i);
  printf("---\n");

  VkInstanceCreateInfo instanceCreateInfo = {
    sType:                   VkStructureType.instanceCreateInfo
  , pNext:                   null
  , flags:                   0
  , pApplicationInfo:        &applicationInfo
  , enabledLayerCount:       cast(uint32_t)(instanceLayers.length)
  , ppEnabledLayerNames:     instanceLayers.ptr
  , enabledExtensionCount:   cast(uint32_t)(instanceExtensions.length)
  , ppEnabledExtensionNames: instanceExtensions.ptr
  };

  // BELOW LEAKS 73,000 bytes of memory, even when destroyed
  //  NVIDIA bug!!!
  vkCreateInstance(&instanceCreateInfo, null, &fw.instance).EnforceVk;
}

////////////////////////////////////////////////////////////////////////////////
void CreateDepthResources(ref Framework fw)
{
  fw.depthImage =
    fw.CreateImage(
      VkImageType.i2D
    , VkFormat.d32Sfloat // use depth find format
    , VkExtent3D(800, 600, 1)
    , VkImageTiling.optimal
    , VkImageUsageFlag.depthStencilAttachmentBit
    , VkMemoryPropertyFlag.deviceLocalBit
    );

  VkImageSubresourceRange subresourceRange = {
    aspectMask:     VkImageAspectFlag.depthBit
  , baseMipLevel:   0
  , levelCount:     1
  , baseArrayLayer: 0
  , layerCount:     1
  };

  fw.CreateImageView(
    fw.depthImage
  , VkImageViewType.i2D
  , VkFormat.d32Sfloat
  , subresourceRange
  );

  fw.TransitionImageLayout(
    fw.depthImage
  , VkFormat.d32Sfloat
  , VkImageLayout.undefined
  , VkImageLayout.depthStencilAttachmentOptimal
  );
}


////////////////////////////////////////////////////////////////////////////////
void CreateSurface(ref Framework fw) {
  // -- create surface
  fw.instance
    .glfwCreateWindowSurface(
      fw.window
    , null
    , &fw.surface
    ).EnforceVk;

  // -- select best format for surface
  VkBool32 supportPresent = VK_FALSE;
  vkGetPhysicalDeviceSurfaceSupportKHR(
    fw.physicalDevice
  , fw.graphicsQueueFamilyIndex
  , fw.surface
  , &supportPresent
  ).EnforceVk;
  supportPresent.EnforceAssert;

  Array!(VkSurfaceFormatKHR) surfaceFormats =
    GetSurfaceFormats(fw.physicalDevice, fw.surface);

  // Can support requested surface format
  if ( surfaceFormats.length == 1
    && surfaceFormats[0].format == VkFormat.undefined )
  {
    fw.surfaceFormat.format = fw.applicationSettings.surfaceFormat;
    fw.surfaceFormat.colorSpace = surfaceFormats[0].colorSpace;
    return;
  }

  // find next best option
  foreach ( ref surfaceFormat; surfaceFormats.AsRange ) {
    if ( surfaceFormat.format == fw.applicationSettings.surfaceFormat ) {
      fw.surfaceFormat = surfaceFormat;
      return;
    }
  }

  // out of luck
  fw.surfaceFormat = surfaceFormats[0];
}

////////////////////////////////////////////////////////////////////////////////
void InitializeDevicesAndQueues(ref Framework fw) {
  fw.physicalDevice = GetPhysicalDevices(fw.instance)[0];
  immutable VkQueueFlag[3] requestedQueueFlags = [
    VkQueueFlag.graphicsBit
  , VkQueueFlag.computeBit
  , VkQueueFlag.transferBit
  ];

  // Can't do [ ~0u, ~0u, ~0u ] as elements are adjacent..:
  // https://issues.dlang.org/show_bug.cgi?id=17778
  uint32_t[3] queueIndices;
  queueIndices[0] = ~0u;
  queueIndices[1] = ~0u;
  queueIndices[2] = ~0u;

  Array!(VkQueueFamilyProperties) queueFamilyProperties =
    GetPhysicalDeviceQueueFamilyProperties(fw.physicalDevice);

  // -- get queue family indices
  foreach ( iter, const requestedQueueFlag; requestedQueueFlags ) {
    uint32_t* queueIdx = &queueIndices[iter];

    foreach ( j; 0 .. queueFamilyProperties.length ) {
      VkQueueFlags queueFlags = queueFamilyProperties[j].queueFlags;

      if (
           (
               (requestedQueueFlag == VkQueueFlag.computeBit)
           &&  (queueFlags & VkQueueFlag.computeBit)
           && !(queueFlags & VkQueueFlag.graphicsBit)
           )
        || (
               (requestedQueueFlag == VkQueueFlag.transferBit)
           &&  (queueFlags & VkQueueFlag.transferBit)
           && !(queueFlags & VkQueueFlag.graphicsBit)
           && !(queueFlags & VkQueueFlag.computeBit)
           )
        || (
             queueFlags & requestedQueueFlag
           )
      ) {
        *queueIdx = cast(uint)j;
        break;
      }
    }
  }

  fw.graphicsQueueFamilyIndex = queueIndices[0];
  fw.computeQueueFamilyIndex  = queueIndices[1];
  fw.transferQueueFamilyIndex = queueIndices[2];

  // -- setup an array of device queue create information
  const float priority = 0.0f;

  VkDeviceQueueCreateInfo deviceQueueCreateInfo = {
    sType:            VkStructureType.deviceQueueCreateInfo
  , pNext:            null
  , flags:            0
  , queueFamilyIndex: fw.graphicsQueueFamilyIndex
  , queueCount:       1
  , pQueuePriorities: &priority
  };

  auto deviceQueueCreateInfos = Array!(VkDeviceQueueCreateInfo)(1);
  deviceQueueCreateInfos[0] = deviceQueueCreateInfo;

  if ( fw.computeQueueFamilyIndex != fw.graphicsQueueFamilyIndex ) {
    deviceQueueCreateInfo.queueFamilyIndex = fw.computeQueueFamilyIndex;
    deviceQueueCreateInfos ~= deviceQueueCreateInfo;
  }

  if ( fw.transferQueueFamilyIndex != fw.graphicsQueueFamilyIndex
    && fw.transferQueueFamilyIndex != fw.computeQueueFamilyIndex
  ) {
    deviceQueueCreateInfo.queueFamilyIndex = fw.transferQueueFamilyIndex ;
    deviceQueueCreateInfos ~= deviceQueueCreateInfo;
  }

  // -- get extensions
   auto deviceExtensions = Array!(const(char)*)(1);
   deviceExtensions[0] = VK_KHR_SWAPCHAIN_EXTENSION_NAME;
   // deviceExtensions[1] = VK_NV_RAY_TRACING_EXTENSION_NAME;
   // deviceExtensions[1] = VK_EXT_DESCRIPTOR_INDEXING_EXTENSION_NAME;

  // -- get physical device descriptor indexing features
  //   and enable all features GPU supports
  VkPhysicalDeviceDescriptorIndexingFeaturesEXT descriptorIndexing = {
    sType: VkStructureType.physicalDeviceDescriptorIndexingFeaturesExt
  , pNext: null
  };

  VkPhysicalDeviceFeatures2 features2 = {
    sType: VkStructureType.physicalDeviceFeatures2
  , pNext: &descriptorIndexing
  };

  fw.physicalDevice.vkGetPhysicalDeviceFeatures2(&features2);

  // -- print out device extensions
  printf("DeviceExtensions:\n");
  foreach ( ref i; deviceExtensions.AsRange )
    printf(" * %s\n", i);
  printf("---\n");


  VkDeviceCreateInfo deviceCreateInfo = {
    sType:                   VkStructureType.deviceCreateInfo
  , pNext:                   &features2
  , flags:                   0
  , queueCreateInfoCount:    cast(uint32_t)(deviceQueueCreateInfos.length)
  , pQueueCreateInfos:       deviceQueueCreateInfos.ptr
  , enabledLayerCount:       0
  , ppEnabledLayerNames:     null
  , enabledExtensionCount:   cast(uint32_t)(deviceExtensions.length)
  , ppEnabledExtensionNames: deviceExtensions.ptr
  , pEnabledFeatures:        null
  };

  fw.physicalDevice
    .vkCreateDevice(
      &deviceCreateInfo
    , null
    , &fw.device
    ).EnforceVk;

  // -- get queue handles
  fw.device.vkGetDeviceQueue(fw.graphicsQueueFamilyIndex, 0, &fw.graphicsQueue);
  fw.device.vkGetDeviceQueue(fw.computeQueueFamilyIndex,  0, &fw.computeQueue);
  fw.device.vkGetDeviceQueue(fw.transferQueueFamilyIndex, 0, &fw.transferQueue);

  // -- get raytracing properties
  VkPhysicalDeviceRayTracingPropertiesNV raytracingProperties = {
    sType : VkStructureType.physicalDeviceRayTracingPropertiesNv
  , pNext : null
  , shaderGroupHandleSize : 0
  , maxRecursionDepth : 0
  , maxShaderGroupStride : 0
  , shaderGroupBaseAlignment : 0
  , maxGeometryCount : 0
  , maxInstanceCount : 0
  , maxTriangleCount : 0
  , maxDescriptorSetAccelerationStructures : 0
  };

  fw.raytracingProperties = raytracingProperties;

  VkPhysicalDeviceProperties2 deviceProperties = {
    sType:      VkStructureType.physicalDeviceProperties2
  , pNext:      &fw.raytracingProperties
  , properties: {}
  };

  fw.physicalDevice.vkGetPhysicalDeviceProperties2(&deviceProperties);

  printf(
`    ----------------------------------------
    RTX 208 Ti Raytracing properties:

    shaderGroupHandleSize: %d
    maxRecursionDepth: %d
    maxShaderGroupStride: %d
    shaderGroupBaseAlignment: %d
    maxGeometryCount: %d
    maxInstanceCount: %d
    maxTriangleCount: %d
    maxDescriptorSetAccelerationStructures: %d
    ----------------------------------------
    `
  , fw.raytracingProperties.shaderGroupHandleSize
  , fw.raytracingProperties.maxRecursionDepth
  , fw.raytracingProperties.maxShaderGroupStride
  , fw.raytracingProperties.shaderGroupBaseAlignment
  , fw.raytracingProperties.maxGeometryCount
  , fw.raytracingProperties.maxInstanceCount
  , fw.raytracingProperties.maxTriangleCount
  , fw.raytracingProperties.maxDescriptorSetAccelerationStructures
  );
}

////////////////////////////////////////////////////////////////////////////////
void FrameBegin(ref Framework fw, float* clearColor) {
  // Wait for previous frame to finish
  fw.device.vkWaitForFences(
    1
  , &fw.fenceFrame[fw.frameIndex]
  , VK_TRUE
  , uint64_t.max
  );

  // Get next frame to be rendered out to
  fw.device.vkAcquireNextImageKHR(
    fw.swapchain
  , uint64_t.max
  , fw.semaphoreImagesAcquired[fw.frameIndex]
  , null
  , &fw.backBufferIndices[fw.frameIndex]
  );

  VkCommandBuffer frameCmdBuffer = fw.commandBuffers[fw.frameIndex];

  { // -- begin command buffer
    VkCommandBufferBeginInfo info = {
      sType:            VkStructureType.commandBufferBeginInfo
    , pNext:            null
    , flags:            VkCommandBufferUsageFlag.oneTimeSubmitBit
    , pInheritanceInfo: null
    };

    frameCmdBuffer
      .vkBeginCommandBuffer(&info)
      .EnforceVk;
  }

  { // -- begin render pass
    VkRect2D renderArea = {
      offset: VkOffset2D(0, 0)
    , extent: VkExtent2D(800, 600)
    };

    auto clearValues = Array!(VkClearValue)(2);

    clearValues[0].color.float32[0] = clearColor[0];
    clearValues[0].color.float32[1] = clearColor[1];
    clearValues[0].color.float32[2] = clearColor[2];
    clearValues[0].color.float32[3] = 1.0f;

    clearValues[1].depthStencil.depth   = 1.0f;
    clearValues[1].depthStencil.stencil = 0;

    VkRenderPassBeginInfo info = {
      sType:           VkStructureType.renderPassBeginInfo
    , pNext:           null
    , renderPass:      fw.renderPass
    , framebuffer:     fw.frameBuffers[fw.frameIndex]
    , renderArea:      renderArea
    , clearValueCount: cast(uint32_t)clearValues.length
    , pClearValues:    clearValues.ptr
    };

    fw.commandBuffers[fw.frameIndex]
      .vkCmdBeginRenderPass(&info, VkSubpassContents.inline);
  }
}

////////////////////////////////////////////////////////////////////////////////
void FrameEnd(ref Framework fw) {

  VkCommandBuffer frameCmdBuffer = fw.commandBuffers[fw.frameIndex];

  // end render pass
  frameCmdBuffer.vkCmdEndRenderPass;

  { // -- Prepare backbuffer image to be presented to screen
    VkImageSubresourceRange subresourceRange = {
      aspectMask:     VkImageAspectFlag.colorBit
    , baseMipLevel:   0
    , levelCount:     1
    , baseArrayLayer: 0
    , layerCount:     1
    };

    VkImageMemoryBarrier barrier = {
      sType:               VkStructureType.imageMemoryBarrier
    , pNext:               null
    , srcAccessMask:       0
    , dstAccessMask:       VkAccessFlag.transferWriteBit
    , oldLayout:           VkImageLayout.undefined
    , newLayout:           VkImageLayout.presentSrcKhr
    , srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED
    , dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED
    , image:               fw.backBuffers[fw.frameIndex]
    , subresourceRange:    subresourceRange
    };

    frameCmdBuffer.vkCmdPipelineBarrier(
      /* srcStageMask */ VkPipelineStageFlag.allCommandsBit
    , /* dstStageMask */ VkPipelineStageFlag.allCommandsBit
    , /* dependencyFlags */ 0
    , /* memoryBarrierCount */ 0
    , /* pMemoryBarriers */ null
    , /* bufferMemoryBarrierCount */ 0
    , /* pBufferMemoryBarriers */ null
    , /* imageMemoryBarrierCount */ 1
    , /* pImageMemoryBarriers */ &barrier
    );
  }

  // end command buffer
  frameCmdBuffer.vkEndCommandBuffer.EnforceVk;

  // fence waits
  VkFence fence = fw.fenceFrame[fw.frameIndex];
  fw.device.vkWaitForFences(1, &fence, VK_TRUE, uint64_t.max);
  fw.device.vkResetFences(1, &fence);

  { // submit out command buffer to graphics queue
    VkPipelineStageFlags waitStage =
      VkPipelineStageFlag.colorAttachmentOutputBit;

      VkSubmitInfo info = {
        sType:                VkStructureType.submitInfo
      , pNext:                null
      , waitSemaphoreCount:   1
      , pWaitSemaphores:      &fw.semaphoreImagesAcquired[fw.frameIndex]
      , pWaitDstStageMask:    &waitStage
      , commandBufferCount:   1
      , pCommandBuffers:      &frameCmdBuffer
      , signalSemaphoreCount: 1
      , pSignalSemaphores:    &fw.semaphoreRendersFinished[fw.frameIndex]
      };

    fw.graphicsQueue
      .vkQueueSubmit(1, &info, fw.fenceFrame[fw.frameIndex])
      .EnforceVk;
  }

  { // Submit backbuffer image present
    uint32_t[1] indices = [ fw.backBufferIndices[fw.frameIndex] ];

    VkPresentInfoKHR info = {
      sType:              VkStructureType.presentInfoKhr
    , pNext:              null
    , waitSemaphoreCount: 1
    , pWaitSemaphores:    &fw.semaphoreRendersFinished[fw.frameIndex]
    , swapchainCount:     1
    , pSwapchains:        &fw.swapchain
    , pImageIndices:      indices.ptr
    , pResults:           null
    };

    fw.graphicsQueue
      .vkQueuePresentKHR(&info)
      .EnforceVk;
  }

  // iterate to next frame index
  fw.frameIndex = (fw.frameIndex + 1) % 2;
}

// Maybe make this a scoped thing?
////////////////////////////////////////////////////////////////////////////////

struct ScopedSingleTimeCommandBuffer {
  VkCommandBuffer cmdBuffer;
  Framework* fw;

  this(ref Framework fw_) {
    Begin(fw_);
  }

  ~this() {
    if (!fw) return;
    End;
  }

  void Begin(ref Framework fw_) {
    fw = &fw_;
    { // -- allocate command buffer
      VkCommandBufferAllocateInfo info = {
        sType:              VkStructureType.commandBufferAllocateInfo
      , pNext:              null
      , commandPool:        fw.commandPools[0]
      , level:              VkCommandBufferLevel.primary
      , commandBufferCount: 1
      };

      fw.device
        .vkAllocateCommandBuffers(&info, &cmdBuffer)
        .EnforceVk;
    }

    { // -- setup command buffer begin
      VkCommandBufferBeginInfo info = {
          sType: VkStructureType.commandBufferBeginInfo
        , pNext: null
        , flags: VkCommandBufferUsageFlag.oneTimeSubmitBit
        , pInheritanceInfo: null
      };

      cmdBuffer.vkBeginCommandBuffer(&info).EnforceVk;
    }
  }

  void End() {
    cmdBuffer.vkEndCommandBuffer;

    { // -- push command buffer submission to graphics queue
      VkSubmitInfo info = {
        sType: VkStructureType.submitInfo
      , pNext: null
      , waitSemaphoreCount: 0
      , pWaitSemaphores: null
      , pWaitDstStageMask: null
      , commandBufferCount: 1
      , pCommandBuffers: &cmdBuffer
      , signalSemaphoreCount: 0
      , pSignalSemaphores: null
      };

      fw.graphicsQueue.vkQueueSubmit(1, &info, null).EnforceVk;
    }

    fw.graphicsQueue.vkQueueWaitIdle;

    fw.device.vkFreeCommandBuffers(fw.commandPools[0], 1, &cmdBuffer);

    fw = null;
  }
}

VkCommandBuffer CreateSingleTimeCommandBuffer(ref Framework fw) {
  VkCommandBuffer commandBuffer;

  return commandBuffer;
}

////////////////////////////////////////////////////////////////////////////////
void EndSingleTimeCommandBuffer(
  ref Framework fw
, VkCommandBuffer commandBuffer
) {
}
