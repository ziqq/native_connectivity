//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <native_connectivity/connectivity_monitor_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) native_connectivity_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "ConnectivityMonitorPlugin");
  connectivity_monitor_plugin_register_with_registrar(native_connectivity_registrar);
}
