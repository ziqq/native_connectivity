#include "include/native_connectivity/connectivity_monitor_plugin.h"

#include <gio/gio.h>

namespace {

constexpr char kChannel[] = "github.com/ziqq/connectivity_monitor";

// The event channel owns the observation and destroys it on engine shutdown.
struct Observation {
  FlEventChannel* channel;
  GNetworkMonitor* monitor;
  gulong handler_id = 0;
};

void Stop(Observation* observation) {
  if (observation->handler_id == 0) return;
  g_signal_handler_disconnect(observation->monitor, observation->handler_id);
  observation->handler_id = 0;
}

void Send(FlEventChannel* channel, const char* status) {
  g_autoptr(FlValue) value = fl_value_new_string(status);
  fl_event_channel_send(channel, value, nullptr, nullptr);
}

void NetworkChanged(GNetworkMonitor*, gboolean available, gpointer data) {
  auto* observation = static_cast<Observation*>(data);
  Send(observation->channel, available ? "satisfied" : "unsatisfied");
}

FlMethodErrorResponse* Listen(FlEventChannel* channel, FlValue*, gpointer data) {
  auto* observation = static_cast<Observation*>(data);
  Stop(observation);
  if (observation->monitor == nullptr) {
    Send(channel, "unknown");
    return nullptr;
  }

  observation->handler_id = g_signal_connect(
      observation->monitor, "network-changed", G_CALLBACK(NetworkChanged), observation);
  NetworkChanged(observation->monitor,
                 g_network_monitor_get_network_available(observation->monitor), observation);
  return nullptr;
}

FlMethodErrorResponse* Cancel(FlEventChannel*, FlValue*, gpointer data) {
  Stop(static_cast<Observation*>(data));
  return nullptr;
}

void Destroy(gpointer data) {
  auto* observation = static_cast<Observation*>(data);
  Stop(observation);
  g_clear_object(&observation->monitor);
  delete observation;
}

}  // namespace

void connectivity_monitor_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlEventChannel) channel = fl_event_channel_new(
      fl_plugin_registrar_get_messenger(registrar), kChannel, FL_METHOD_CODEC(codec));
  auto* monitor = g_network_monitor_get_default();
  auto* observation = new Observation{channel, monitor == nullptr ? nullptr : G_NETWORK_MONITOR(g_object_ref(monitor))};
  fl_event_channel_set_stream_handlers(channel, Listen, Cancel, observation, Destroy);
}
