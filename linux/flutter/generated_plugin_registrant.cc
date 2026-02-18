//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <keyboard_height/keyboard_height_linux.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) keyboard_height_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "KeyboardHeightLinux");
  keyboard_height_linux_register_with_registrar(keyboard_height_registrar);
}
