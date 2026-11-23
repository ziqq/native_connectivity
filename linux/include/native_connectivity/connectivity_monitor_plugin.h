#ifndef NATIVE_CONNECTIVITY_CONNECTIVITY_MONITOR_PLUGIN_H_
#define NATIVE_CONNECTIVITY_CONNECTIVITY_MONITOR_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

G_MODULE_EXPORT void connectivity_monitor_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // NATIVE_CONNECTIVITY_CONNECTIVITY_MONITOR_PLUGIN_H_
