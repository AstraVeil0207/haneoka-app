#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  team_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "org.haneoka/team_engine",
      &flutter::StandardMethodCodec::GetInstance());
  team_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    const std::string* key = nullptr;
    if (args) {
      auto found = args->find(flutter::EncodableValue("key"));
      if (found != args->end()) key = std::get_if<std::string>(&found->second);
    }
    if (!key || key->empty()) { result->Error("engine-key", "Missing engine key"); return; }
    if (call.method_name() == "dispose") {
      team_engines_.erase(*key); result->Success(); return;
    }
    if (call.method_name() != "start") { result->NotImplemented(); return; }
    if (team_engines_.find(*key) == team_engines_.end()) {
      auto project = project_;
      project.set_dart_entrypoint_arguments({"--haneoka-team-engine=" + *key});
      project.set_ui_thread_policy(flutter::UIThreadPolicy::RunOnSeparateThread);
      auto engine = std::make_unique<flutter::FlutterEngine>(project);
      if (!engine->Run()) { result->Error("engine-start", "Could not start team engine"); return; }
      team_engines_.emplace(*key, std::move(engine));
    }
    result->Success();
  });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (team_channel_) team_channel_->SetMethodCallHandler(nullptr);
  team_channel_.reset();
  team_engines_.clear();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
