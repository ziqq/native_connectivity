#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <ipifcons.h>

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>
#include <utility>

#include "include/native_connectivity/connectivity_monitor_plugin_c_api.h"

namespace {

constexpr char kChannel[] = "github.com/ziqq/connectivity_monitor";
using Value = flutter::EncodableValue;
using Sink = flutter::EventSink<Value>;
using Error = flutter::StreamHandlerError<Value>;

const char* ReadPath() {
  PMIB_IPFORWARD_TABLE2 routes = nullptr;
  const auto result = GetIpForwardTable2(AF_UNSPEC, &routes);
  if (result == ERROR_NOT_FOUND) return "unsatisfied";
  if (result != NO_ERROR) return "unknown";

  const std::unique_ptr<MIB_IPFORWARD_TABLE2, decltype(&FreeMibTable)> table(routes, FreeMibTable);
  bool has_unknown_interface = false;
  for (ULONG index = 0; index < table->NumEntries; ++index) {
    const auto& route = table->Table[index];
    if (route.DestinationPrefix.PrefixLength != 0) continue;

    MIB_IF_ROW2 interface_row{};
    interface_row.InterfaceLuid = route.InterfaceLuid;
    if (GetIfEntry2(&interface_row) != NO_ERROR) {
      has_unknown_interface = true;
      continue;
    }
    if (interface_row.OperStatus == IfOperStatusUp &&
        interface_row.Type != IF_TYPE_SOFTWARE_LOOPBACK) {
      return "satisfied";
    }
  }
  return has_unknown_interface ? "unknown" : "unsatisfied";
}

// IP Helper invokes these callbacks outside Flutter's platform thread.
struct Watch {
  HWND window;
  UINT message;
  WPARAM owner;
  LPARAM subscription;

  void Notify() const { PostMessageW(window, message, owner, subscription); }
};

void CALLBACK RouteChanged(void* context, PMIB_IPFORWARD_ROW2 route, MIB_NOTIFICATION_TYPE) {
  if (route != nullptr && route->DestinationPrefix.PrefixLength == 0) {
    static_cast<const Watch*>(context)->Notify();
  }
}

void CALLBACK InterfaceChanged(void* context, PMIB_IPINTERFACE_ROW, MIB_NOTIFICATION_TYPE) {
  static_cast<const Watch*>(context)->Notify();
}

class ConnectivityMonitorPlugin final : public flutter::Plugin {
 public:
  explicit ConnectivityMonitorPlugin(flutter::PluginRegistrarWindows* registrar)
      : registrar_(registrar),
        notification_(RegisterWindowMessageW(L"github.com/ziqq/connectivity_monitor")),
        channel_(registrar->messenger(), kChannel, &flutter::StandardMethodCodec::GetInstance()) {
    delegate_ = registrar_->RegisterTopLevelWindowProcDelegate(
        [this](HWND window, UINT message, WPARAM owner, LPARAM subscription) -> std::optional<LRESULT> {
          if (events_ && watch_ && window == watch_->window && message == notification_ &&
              owner == watch_->owner && subscription == watch_->subscription) {
            events_->Success(Value(ReadPath()));
            return 0;
          }
          return std::nullopt;
        });
    channel_.SetStreamHandler(std::make_unique<flutter::StreamHandlerFunctions<Value>>(
        [this](const Value*, std::unique_ptr<Sink>&& events) -> std::unique_ptr<Error> {
          Listen(std::move(events));
          return nullptr;
        },
        [this](const Value*) -> std::unique_ptr<Error> {
          Cancel();
          return nullptr;
        }));
  }

  ~ConnectivityMonitorPlugin() override {
    channel_.SetStreamHandler(nullptr);
    Cancel();
    registrar_->UnregisterTopLevelWindowProcDelegate(delegate_);
  }

 private:
  void Listen(std::unique_ptr<Sink> events) {
    Cancel();
    events_ = std::move(events);
    auto* view = registrar_->GetView();
    const auto window = view == nullptr ? nullptr : GetAncestor(view->GetNativeWindow(), GA_ROOT);
    if (window == nullptr || notification_ == 0) {
      events_->Success(Value("unknown"));
      return;
    }

    // A queued message can outlive the subscription that posted it.
    watch_ = std::make_unique<Watch>(Watch{window, notification_, reinterpret_cast<WPARAM>(this), ++subscription_});
    if (NotifyRouteChange2(AF_UNSPEC, RouteChanged, watch_.get(), FALSE, &routes_) != NO_ERROR ||
        NotifyIpInterfaceChange(AF_UNSPEC, InterfaceChanged, watch_.get(), FALSE, &interfaces_) != NO_ERROR) {
      events_->Success(Value("unknown"));
      Cancel();
      return;
    }
    events_->Success(Value(ReadPath()));
  }

  void Cancel() {
    events_.reset();
    if (routes_ != nullptr) CancelMibChangeNotify2(std::exchange(routes_, nullptr));
    if (interfaces_ != nullptr) CancelMibChangeNotify2(std::exchange(interfaces_, nullptr));
    watch_.reset();
  }

  flutter::PluginRegistrarWindows* const registrar_;
  const UINT notification_;
  flutter::EventChannel<Value> channel_;
  int delegate_ = 0;
  LPARAM subscription_ = 0;
  HANDLE routes_ = nullptr;
  HANDLE interfaces_ = nullptr;
  std::unique_ptr<Watch> watch_;
  std::unique_ptr<Sink> events_;
};

}  // namespace

void ConnectivityMonitorPluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  auto* windows_registrar = flutter::PluginRegistrarManager::GetInstance()
                                ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  windows_registrar->AddPlugin(std::make_unique<ConnectivityMonitorPlugin>(windows_registrar));
}
