module imgui;

import core.stdc.stdint;

import glfw;

// Adapted from Derelict IMGUI for BetterC usage

// probably in future don't want this to be public import, just have D bindings
//   w/ neo support
public import cimgui;
public import cimgui_glfw;
public import cimgui_vk;

import vk;
import vkcontext;
import utility;

struct CimguiInfo {
  GLFWwindow *   window;
  ImGuiContext * context;
};

CimguiInfo cInfo;

nothrow static void ImguiCheckVkResult(VkResult err) {
  import core.stdc.stdio;

  if (err == 0)
    return;

  printf("Imgui error: VkResult %d\n", err);

  if (err < 0) {
    import core.stdc.stdlib;
    import core.stdc.signal;
    raise(SIGABRT);
    exit(-1);
  }
}

void InitializeGlfwVulkanImgui(ref Framework fw) {
  cInfo.context = igCreateContext(null);

  // -- initialize imgui
  ImGui_ImplGlfw_InitForVulkan(fw.window, true);
  ImGui_ImplVulkan_InitInfo initInfo = {
    Instance:        fw.instance
  , PhysicalDevice:  fw.physicalDevice
  , Device:          fw.device
  , QueueFamily:     fw.graphicsQueueFamilyIndex
  , Queue:           fw.graphicsQueue
  , PipelineCache:   fw.pipelineCache
  , DescriptorPool:  fw.descriptorPool
  , Allocator:       null
  , CheckVkResultFn: &ImguiCheckVkResult
  };
  ImGui_ImplVulkan_Init(&initInfo, fw.renderPass);

  igStyleColorsDark(null);

  // upload fonts

  { // -- upload fonts
    uint32_t frameIndex = 0;

    fw.device.vkResetCommandPool(fw.commandPools[frameIndex], 0);

    { // -- begin commandbuffer for fonts
      VkCommandBufferBeginInfo info = {
        sType:            VkStructureType.commandBufferBeginInfo
      , pNext:            null
      , flags:            VkCommandBufferUsageFlag.oneTimeSubmitBit
      , pInheritanceInfo: null
      };

      fw.commandBuffers[frameIndex].vkBeginCommandBuffer(&info);
    }

    ImGui_ImplVulkan_CreateFontsTexture(fw.commandBuffers[frameIndex]);

  // -- end command buffer
    fw.commandBuffers[frameIndex]
      .vkEndCommandBuffer;

    { // -- submit font texture creation to graphics queue
      VkSubmitInfo info = {
        sType:                VkStructureType.submitInfo
      , pNext:                null
      , waitSemaphoreCount:   0
      , pWaitSemaphores:      null
      , pWaitDstStageMask:    null
      , commandBufferCount:   1
      , pCommandBuffers:      &fw.commandBuffers[frameIndex]
      , signalSemaphoreCount: 0
      , pSignalSemaphores:    null
      };

      // -- submit queue
      fw.graphicsQueue
        .vkQueueSubmit(1, &info, null)
        .EnforceVk;
    }

    fw.device.vkDeviceWaitIdle.EnforceVk;

    ImGui_ImplVulkan_InvalidateFontUploadObjects();
  }
}
