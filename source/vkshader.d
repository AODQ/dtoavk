module vkshader;

import utility;
import vkcontext;

import core.stdc.stdint;
import neobc.array;
import vk;

VkShaderModule LoadShaderModule(ref Framework fw , string fileName) {
  import core.stdc.stdio;

  VkShaderModule shader;

  printf("Loading shader: %s\n", fileName.ptr);

  // read file into fileBuffer (C way, maybe write BC files library? eh...)
  FILE * file = fopen(fileName.ptr, "rb");
  EnforceAssert(file, "Could not open file");
  fseek(file, 0, SEEK_END);
  auto fileLength = ftell(file);
  rewind(file);
  auto fileBuffer = Array!(uint32_t)(fileLength);
  fread(fileBuffer.ptr, fileLength, 1, file);
  fclose(file);

  printf("FILE [%d]\n", fileBuffer.length);

  VkShaderModuleCreateInfo shaderModuleCreateInfo = {
    sType: VkStructureType.shaderModuleCreateInfo
  , pNext: null
  , codeSize: fileBuffer.length
  , pCode: cast(uint32_t*)(fileBuffer.ptr)
  , flags: 0
  };

  fw.device
    .vkCreateShaderModule(&shaderModuleCreateInfo, null, &shader)
    .EnforceVk;

  return shader;
}
