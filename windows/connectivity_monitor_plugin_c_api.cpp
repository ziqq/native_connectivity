#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <ipifcons.h>

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <cstdint>
#include <limits>
#include <memory>
#include <optional>
#include <utility>

#include "include/native_connectivity/connectivity_monitor_plugin_c_api.h"

namespace {

constexpr char kChannel[] = "github.com/ziqq/connectivity_monitor";
constexpr UINT kRetryDelayMillis = 1000;
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
          if (retry_timer_ != 0 && window == window_ && message == WM_TIMER && owner == retry_timer_) {
            StopRetry();
            Register(false);
            return 0;
          }
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
    window_ = view == nullptr ? nullptr : GetAncestor(view->GetNativeWindow(), GA_ROOT);
    if (window_ == nullptr || notification_ == 0) {
      events_->Success(Value("unknown"));
      return;
    }
    Register(true);
  }

  void Register(bool retry_on_failure) {
    // A queued message can outlive the subscription that posted it.
    watch_ = std::make_unique<Watch>(Watch{window_, notification_, reinterpret_cast<WPARAM>(this), ++subscription_});
    auto error = NotifyRouteChange2(AF_UNSPEC, RouteChanged, watch_.get(), FALSE, &routes_);
#if defined(NATIVE_CONNECTIVITY_TEST_FAIL_INTERFACE)
    // The integration test exercises rollback after a real route registration.
    if (error == NO_ERROR && retry_on_failure) error = ERROR_RETRY;
#endif
    if (error == NO_ERROR) {
      error = NotifyIpInterfaceChange(AF_UNSPEC, InterfaceChanged, watch_.get(), FALSE, &interfaces_);
    }
    if (error == NO_ERROR) {
      events_->Success(Value(ReadPath()));
      return;
    }

    StopWatching();
    if (retry_on_failure) {
      // KillTimer can leave queued messages. A fresh ID keeps them separate from later subscriptions.
      static std::atomic<UINT_PTR> next_timer{UINT_PTR{1} << (std::numeric_limits<UINT_PTR>::digits - 1)};
      const auto id = next_timer.fetch_add(1, std::memory_order_relaxed);
      if (SetTimer(window_, id, kRetryDelayMillis, nullptr) != 0) retry_timer_ = id;
    }
    events_->Error("network_callback_failed", "Network callback registration failed", Value(static_cast<int64_t>(error)));
  }

  void Cancel() {
    StopRetry();
    StopWatching();
    events_.reset();
    window_ = nullptr;
  }

  void StopRetry() {
    if (retry_timer_ != 0) KillTimer(window_, std::exchange(retry_timer_, 0));
  }

  void StopWatching() {
    if (routes_ != nullptr) CancelMibChangeNotify2(std::exchange(routes_, nullptr));
    if (interfaces_ != nullptr) CancelMibChangeNotify2(std::exchange(interfaces_, nullptr));
    watch_.reset();
  }

  flutter::PluginRegistrarWindows* const registrar_;
  const UINT notification_;
  flutter::EventChannel<Value> channel_;
  int delegate_ = 0;
  LPARAM subscription_ = 0;
  HWND window_ = nullptr;
  UINT_PTR retry_timer_ = 0;
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
