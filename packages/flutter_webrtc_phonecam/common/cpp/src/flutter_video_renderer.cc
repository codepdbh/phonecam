#include "flutter_video_renderer.h"

#if defined(_WINDOWS)
#include <windows.h>
#include <chrono>
#include <cstring>
#endif

namespace flutter_webrtc_plugin {

namespace {
// Maps a destination pixel coordinate in a `rotation`-corrected image back to
// its source coordinate in the original (unrotated) srcW x srcH buffer.
// Shared by the on-screen texture path (CopyPixelBuffer) and the virtual
// camera publish path (PublishPhoneCamFrame) — both need to physically
// rotate raw sensor-orientation pixels since neither Flutter's Texture
// widget nor a DirectShow/MF sample carries rotation as separate metadata.
inline void RotatedSourceCoord(RTCVideoFrame::VideoRotation rotation, int dx, int dy,
                               int srcW, int srcH, int& sx, int& sy) {
  switch (rotation) {
    case RTCVideoFrame::kVideoRotation_90:
      sx = dy; sy = (srcH - 1) - dx; break;
    case RTCVideoFrame::kVideoRotation_180:
      sx = (srcW - 1) - dx; sy = (srcH - 1) - dy; break;
    case RTCVideoFrame::kVideoRotation_270:
      sx = (srcW - 1) - dy; sy = dx; break;
    default:
      sx = dx; sy = dy; break;
  }
}
}  // namespace

FlutterVideoRenderer::~FlutterVideoRenderer() {}

void FlutterVideoRenderer::initialize(
    TextureRegistrar* registrar,
    BinaryMessenger* messenger,
    TaskRunner* task_runner,
    std::unique_ptr<flutter::TextureVariant> texture,
    int64_t trxture_id) {
  registrar_ = registrar;
  texture_ = std::move(texture);
  texture_id_ = trxture_id;
  std::string channel_name =
      "FlutterWebRTC/Texture" + std::to_string(texture_id_);
  event_channel_ = EventChannelProxy::Create(messenger, task_runner, channel_name);
}

const FlutterDesktopPixelBuffer* FlutterVideoRenderer::CopyPixelBuffer(
    size_t width,
    size_t height) const {
  mutex_.lock();
  if (pixel_buffer_.get() && frame_.get()) {
    const int rawWidth = frame_->width();
    const int rawHeight = frame_->height();
    // ConvertToARGB() below has no rotation parameter — it always converts
    // the raw sensor-orientation buffer. RTCVideoValue.aspectRatio on the
    // Dart side already swaps width/height for a 90/270 rotation when
    // sizing the widget (see rtc_video_renderer.dart), so leaving the pixel
    // content unrotated stretches it into the wrong-shaped box. Rotate here
    // so the texture's actual content matches what the widget expects.
    const RTCVideoFrame::VideoRotation rotation = frame_->rotation();
    const bool swapDims = rotation == RTCVideoFrame::kVideoRotation_90 ||
                          rotation == RTCVideoFrame::kVideoRotation_270;
    const int outWidth = swapDims ? rawHeight : rawWidth;
    const int outHeight = swapDims ? rawWidth : rawHeight;

    if (pixel_buffer_->width != static_cast<size_t>(outWidth) ||
        pixel_buffer_->height != static_cast<size_t>(outHeight)) {
      const size_t buffer_size =
          static_cast<size_t>(outWidth) * static_cast<size_t>(outHeight) * 4;
      rgb_buffer_.reset(new uint8_t[buffer_size]);
      pixel_buffer_->width = outWidth;
      pixel_buffer_->height = outHeight;
    }

    if (rotation == RTCVideoFrame::kVideoRotation_0) {
      frame_->ConvertToARGB(RTCVideoFrame::Type::kABGR, rgb_buffer_.get(), 0,
                            outWidth, outHeight);
    } else {
      // Convert at the raw (unrotated) size into a scratch buffer, then
      // rotate the packed ARGB pixels into the final, correctly-shaped one.
      const size_t rawBufferSize =
          static_cast<size_t>(rawWidth) * static_cast<size_t>(rawHeight) * 4;
      if (rotate_scratch_buffer_.size() != rawBufferSize) {
        rotate_scratch_buffer_.resize(rawBufferSize);
      }
      frame_->ConvertToARGB(RTCVideoFrame::Type::kABGR,
                            rotate_scratch_buffer_.data(), 0, rawWidth, rawHeight);
      const auto* src =
          reinterpret_cast<const uint32_t*>(rotate_scratch_buffer_.data());
      auto* dst = reinterpret_cast<uint32_t*>(rgb_buffer_.get());
      for (int dy = 0; dy < outHeight; ++dy) {
        uint32_t* rowOut = dst + static_cast<size_t>(dy) * outWidth;
        for (int dx = 0; dx < outWidth; ++dx) {
          int sx, sy;
          RotatedSourceCoord(rotation, dx, dy, rawWidth, rawHeight, sx, sy);
          rowOut[dx] = src[static_cast<size_t>(sy) * rawWidth + sx];
        }
      }
    }

    pixel_buffer_->buffer = rgb_buffer_.get();
    mutex_.unlock();
    return pixel_buffer_.get();
  }
  mutex_.unlock();
  return nullptr;
}

void FlutterVideoRenderer::OnFrame(scoped_refptr<RTCVideoFrame> frame) {
#if defined(_WINDOWS)
  PublishPhoneCamFrame(frame);
#endif
  if (!first_frame_rendered) {
    EncodableMap params;
    params[EncodableValue("event")] = "didFirstFrameRendered";
    params[EncodableValue("id")] = EncodableValue(texture_id_);
    event_channel_->Success(EncodableValue(params));
    pixel_buffer_.reset(new FlutterDesktopPixelBuffer());
    pixel_buffer_->width = 0;
    pixel_buffer_->height = 0;
    first_frame_rendered = true;
  }
  if (rotation_ != frame->rotation()) {
    EncodableMap params;
    params[EncodableValue("event")] = "didTextureChangeRotation";
    params[EncodableValue("id")] = EncodableValue(texture_id_);
    params[EncodableValue("rotation")] =
        EncodableValue((int32_t)frame->rotation());
    event_channel_->Success(EncodableValue(params));
    rotation_ = frame->rotation();
  }
  if (last_frame_size_.width != frame->width() ||
      last_frame_size_.height != frame->height()) {
    EncodableMap params;
    params[EncodableValue("event")] = "didTextureChangeVideoSize";
    params[EncodableValue("id")] = EncodableValue(texture_id_);
    params[EncodableValue("width")] = EncodableValue((int32_t)frame->width());
    params[EncodableValue("height")] = EncodableValue((int32_t)frame->height());
    event_channel_->Success(EncodableValue(params));

    last_frame_size_ = {(size_t)frame->width(), (size_t)frame->height()};
  }
  mutex_.lock();
  frame_ = frame;
  mutex_.unlock();
  registrar_->MarkTextureFrameAvailable(texture_id_);
}

#if defined(_WINDOWS)
void FlutterVideoRenderer::PublishPhoneCamFrame(
    const scoped_refptr<RTCVideoFrame>& frame) {
  if (!frame || frame->width() <= 0 || frame->height() <= 0 ||
      (frame->width() & 1) || (frame->height() & 1)) {
    return;
  }
  if (!phonecam_push_nv12_) {
    HMODULE module = GetModuleHandleW(L"PhoneCamMediaSource_v7.dll");
    if (!module) module = LoadLibraryW(L"PhoneCamMediaSource_v7.dll");
    if (!module) return;
    phonecam_push_nv12_ = reinterpret_cast<PhoneCamPushNV12Fn>(
        GetProcAddress(module, "PhoneCam_PushNV12Frame"));
    if (!phonecam_push_nv12_) return;
    // Best-effort: if unavailable, PublishPhoneCamFrame() below falls back
    // to a nominal 30fps rather than failing the whole publish path.
    phonecam_get_fps_ = reinterpret_cast<PhoneCamGetFpsFn>(
        GetProcAddress(module, "PhoneCam_GetConfiguredFps"));
  }

  const int src_width = frame->width();
  const int src_height = frame->height();
  // WebRTC keeps the sensor's raw (usually landscape) buffer and ships the
  // display rotation as separate per-frame metadata; the Flutter texture
  // path only ever applies it as a widget-level transform (see
  // didTextureChangeRotation in rtc_video_renderer_impl.dart), never to the
  // pixels themselves. A virtual camera sample has no such metadata channel
  // — Meet/Zoom/OpenCV would just render the raw sensor orientation — so the
  // pixels have to be physically rotated here before publishing.
  const RTCVideoFrame::VideoRotation rotation = frame->rotation();
  const bool swapDims = rotation == RTCVideoFrame::kVideoRotation_90 ||
                        rotation == RTCVideoFrame::kVideoRotation_270;
  const int width = swapDims ? src_height : src_width;
  const int height = swapDims ? src_width : src_height;

  const size_t y_size = static_cast<size_t>(width) * height;
  phonecam_nv12_buffer_.resize(y_size + y_size / 2);
  uint8_t* y_out = phonecam_nv12_buffer_.data();
  uint8_t* uv_out = y_out + y_size;

  const uint8_t* srcY = frame->DataY();
  const int strideY = frame->StrideY();
  const uint8_t* srcU = frame->DataU();
  const int strideU = frame->StrideU();
  const uint8_t* srcV = frame->DataV();
  const int strideV = frame->StrideV();

  if (rotation == RTCVideoFrame::kVideoRotation_0) {
    // Fast path: no rotation needed, straight plane copies like before.
    for (int row = 0; row < height; ++row) {
      std::memcpy(y_out + static_cast<size_t>(row) * width,
                  srcY + static_cast<size_t>(row) * strideY, width);
    }
    for (int row = 0; row < height / 2; ++row) {
      const uint8_t* u = srcU + static_cast<size_t>(row) * strideU;
      const uint8_t* v = srcV + static_cast<size_t>(row) * strideV;
      uint8_t* uv = uv_out + static_cast<size_t>(row) * width;
      for (int col = 0; col < width / 2; ++col) {
        uv[col * 2] = u[col];
        uv[col * 2 + 1] = v[col];
      }
    }
  } else {
    // Rotate Y (full resolution) and U/V (half resolution, 4:2:0) by mapping
    // each destination sample back to its source coordinate.
    for (int dy = 0; dy < height; ++dy) {
      uint8_t* rowOut = y_out + static_cast<size_t>(dy) * width;
      for (int dx = 0; dx < width; ++dx) {
        int sx, sy;
        RotatedSourceCoord(rotation, dx, dy, src_width, src_height, sx, sy);
        rowOut[dx] = srcY[static_cast<size_t>(sy) * strideY + sx];
      }
    }
    const int srcChromaW = src_width / 2;
    const int srcChromaH = src_height / 2;
    const int chromaW = width / 2;
    const int chromaH = height / 2;
    for (int dy = 0; dy < chromaH; ++dy) {
      uint8_t* rowOut = uv_out + static_cast<size_t>(dy) * width;
      for (int dx = 0; dx < chromaW; ++dx) {
        int sx, sy;
        RotatedSourceCoord(rotation, dx, dy, srcChromaW, srcChromaH, sx, sy);
        rowOut[dx * 2] = srcU[static_cast<size_t>(sy) * strideU + sx];
        rowOut[dx * 2 + 1] = srcV[static_cast<size_t>(sy) * strideV + sx];
      }
    }
  }

  const auto timestamp_us = std::chrono::duration_cast<std::chrono::microseconds>(
      std::chrono::steady_clock::now().time_since_epoch()).count();
  const int fps = phonecam_get_fps_ ? phonecam_get_fps_() : 30;
  phonecam_push_nv12_(width, height, fps > 0 ? fps : 30,
                      phonecam_nv12_buffer_.data(),
                      phonecam_nv12_buffer_.size(), timestamp_us);
}
#endif

void FlutterVideoRenderer::SetVideoTrack(scoped_refptr<RTCVideoTrack> track) {
  if (track_ != track) {
    if (track_)
      track_->RemoveRenderer(this);
    track_ = track;
    last_frame_size_ = {0, 0};
    first_frame_rendered = false;
    if (track_)
      track_->AddRenderer(this);
  }
}

bool FlutterVideoRenderer::CheckMediaStream(std::string mediaId) {
  if (0 == mediaId.size() || 0 == media_stream_id.size()) {
    return false;
  }
  return mediaId == media_stream_id;
}

bool FlutterVideoRenderer::CheckVideoTrack(std::string mediaId) {
  if (0 == mediaId.size() || !track_) {
    return false;
  }
  return mediaId == track_->id().std_string();
}

FlutterVideoRendererManager::FlutterVideoRendererManager(
    FlutterWebRTCBase* base)
    : base_(base) {}

void FlutterVideoRendererManager::CreateVideoRendererTexture(
    std::unique_ptr<MethodResultProxy> result) {
  auto texture = new RefCountedObject<FlutterVideoRenderer>();
  auto textureVariant =
      std::make_unique<flutter::TextureVariant>(flutter::PixelBufferTexture(
          [texture](size_t width,
                    size_t height) -> const FlutterDesktopPixelBuffer* {
            return texture->CopyPixelBuffer(width, height);
          }));

  auto texture_id = base_->textures_->RegisterTexture(textureVariant.get());
  texture->initialize(base_->textures_, base_->messenger_, base_->task_runner_,
                      std::move(textureVariant), texture_id);
  renderers_[texture_id] = texture;
  EncodableMap params;
  params[EncodableValue("textureId")] = EncodableValue(texture_id);
  result->Success(EncodableValue(params));
}

void FlutterVideoRendererManager::VideoRendererSetSrcObject(
    int64_t texture_id,
    const std::string& stream_id,
    const std::string& owner_tag,
    const std::string& track_id) {
  scoped_refptr<RTCMediaStream> stream =
      base_->MediaStreamForId(stream_id, owner_tag);

  auto it = renderers_.find(texture_id);
  if (it != renderers_.end()) {
    FlutterVideoRenderer* renderer = it->second.get();
    if (stream.get()) {
      auto video_tracks = stream->video_tracks();
      if (video_tracks.size() > 0) {
        if (track_id == std::string()) {
          renderer->SetVideoTrack(video_tracks[0]);
        } else {
          for (auto track : video_tracks.std_vector()) {
            if (track->id().std_string() == track_id) {
              renderer->SetVideoTrack(track);
              break;
            }
          }
        }
        renderer->media_stream_id = stream_id;
      }
    } else {
      renderer->SetVideoTrack(nullptr);
    }
  }
}

void FlutterVideoRendererManager::VideoRendererDispose(
    int64_t texture_id,
    std::unique_ptr<MethodResultProxy> result) {
  auto it = renderers_.find(texture_id);
  if (it != renderers_.end()) {
    it->second->SetVideoTrack(nullptr);
#if defined(_WINDOWS)
    base_->textures_->UnregisterTexture(texture_id,
                                        [&, it] { renderers_.erase(it); });
#else
    base_->textures_->UnregisterTexture(texture_id);
    renderers_.erase(it);
#endif
    result->Success();
    return;
  }
  result->Error("VideoRendererDisposeFailed",
                "VideoRendererDispose() texture not found!");
}

}  // namespace flutter_webrtc_plugin
