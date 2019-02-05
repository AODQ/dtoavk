import vkcontext;

import core.stdc.stdint;
import core.stdc.stdio;

import neobc.array;

import glfw;
import imgui;
import utility;
import vk;

void InitializeDebugReportCallback(ref Framework fw) {
  if (!fw.applicationSettings.enableValidation) return;
  VkDebugReportCallbackCreateInfoEXT callbackCreateInfo = {
    sType       : VkStructureType.debugReportCallbackCreateInfoExt
  , pNext       : null
  , flags       : VkDebugReportFlagEXT.errorBitExt
                | VkDebugReportFlagEXT.warningBitExt
                | VkDebugReportFlagEXT.performanceWarningBitExt
                // | VkDebugReportFlagEXT.informationBitExt
  , pfnCallback : &VkStandardDebugReportCallback
  , pUserData   : null
  };

  {
    VkDebugReportCallbackEXT callback;
    fw.instance
      .vkCreateDebugReportCallback(&callbackCreateInfo, null, &callback)
      .EnforceVk;
  }
}

Framework InitializeFramework(ApplicationSettings applicationSettings) {
  Framework fw = Framework(applicationSettings);
  "InitializeWindow\n"             .printf; fw.InitializeWindow;
  "InitializeVulkan\n"             .printf; fw.InitializeVulkan;
  "InitializeDevicesAndQueues\n"   .printf; fw.InitializeDevicesAndQueues;
  "LoadVkFunctionExtensions\n"     .printf; fw.device.LoadVkFunctionExtensions;
  "InitializeDebugReportCallback\n".printf; fw.InitializeDebugReportCallback;
  "CreateSurface\n"                .printf; fw.CreateSurface;
  "CreateCommandBuffers\n"         .printf; fw.CreateCommandBuffers;
  "CreateDescriptorPool\n"         .printf; fw.CreateDescriptorPool;
  "CreateSwapchain\n"              .printf; fw.CreateSwapchain;
  "CreateRenderPass\n"             .printf; fw.CreateRenderPass;
  "CreateSwapchainImageViews\n"    .printf; fw.CreateSwapchainImageViews;
  "CreateDepthResources\n"         .printf; fw.CreateDepthResources;
  "CreateFrameBuffer\n"            .printf; fw.CreateFrameBuffer;
  return fw;
}

bool ShouldCloseApplication(ref Framework fw) {
  glfwPollEvents();
  return cast(bool)fw.window.glfwWindowShouldClose;
}

version(linux) void sleepThread(size_t nanoseconds) {
  import core.sys.posix.unistd, core.sys.posix.time;

  timespec requestedTime = {
    tv_sec:   0
  , tv_nsec: nanoseconds
  };
  timespec remainingTime;

  nanosleep(&requestedTime, &remainingTime);
}

extern(C) int main (int argc, char** argv) {
  ApplicationSettings applicationSettings = {
    name:              "raytracing"
  , windowResolutionX: 800
  , windowResolutionY: 600
  , surfaceFormat:     VkFormat.r8g8b8Unorm
  , enableValidation:  true
  , enableVSync:       true
  };

  auto fw = InitializeFramework(applicationSettings);
  "Initialized framework\n".printf;

  "Initializing GlfwVulkanImgui\n".printf; fw.InitializeGlfwVulkanImgui;

  "Entering rendering loop\n".printf;
  float lastFrameTime = glfwGetTime(), currentFrameTime = glfwGetTime();
  while ( !fw.ShouldCloseApplication )
  {
    sleepThread(10_000_000);
    lastFrameTime = currentFrameTime;
    currentFrameTime = glfwGetTime();

    static float[3] clearColor = [0.0f, 0.0f, 0.0f];

    fw.FrameBegin(clearColor.ptr);
    scope(exit) fw.FrameEnd;

    ImGui_ImplVulkan_NewFrame;
    ImGui_ImplGlfw_NewFrame;
    igNewFrame;

    { // simple Ig window
      igColorEdit3("clear color", clearColor, ImGuiColorEditFlags.none);

      igText(
        "Framerate: %.3f ms/frame (%d FPS), total time: %.3f",
        (currentFrameTime - lastFrameTime)*1000.0f,
        cast(int)(1.0f/(currentFrameTime - lastFrameTime)),
        glfwGetTime()
      );
    }

    { // -- rasterize
      // fw.RCommandBuffer
        // .vkCmdBindPipeline(
          // VkPipelineBindPoint.graphics
        // , 
        // );
    }

    igRender;

    ImGui_ImplVulkan_RenderDrawData(
      igGetDrawData
    , fw.commandBuffers[fw.frameIndex]
    );
  }

  printf("-----------------------------------------------------------------\n");
  printf("-- ENDING -------------------------------------------------------\n");
  printf("-----------------------------------------------------------------\n");
  return 0;
}
