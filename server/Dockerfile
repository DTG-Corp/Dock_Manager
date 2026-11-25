# GPU-enabled image: CUDA 12.8 runtime + Python 3.12 (Ubuntu 24.04)
# 24.04 ships GStreamer 1.24 whose nvcodec plugin exposes cudaconvertscale
# (GPU colour-convert). 22.04 ships 1.20 which lacks it, forcing CPU convert.
FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DEFAULT_TIMEOUT=120 \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility,video

# System deps + Python 3.12 (default on 24.04, no PPA needed) + GStreamer NVDEC stack.
# gstreamer1.0-plugins-bad ships libgstnvcodec.so (nvh264dec/nvh265dec/cudaconvertscale/cudadownload).
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    python3.12 \
    python3.12-dev \
    python3.12-venv \
    libpq-dev \
    libgl1 \
    libglib2.0-0 \
    libgomp1 \
    curl \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    libgstreamer1.0-0 \
    libgstreamer-plugins-base1.0-0 \
    cuda-nvrtc-12-8 \
    && apt-get purge -y python3-blinker || true \
    && rm -rf /var/lib/apt/lists/*

# nvcodec's cudaconvertscale JIT-compiles its kernel via libnvrtc and dlopen()s the
# UNVERSIONED name "libnvrtc.so"; the runtime package only ships libnvrtc.so.12.
# Without this symlink the element is silently dropped and we fall back to CPU convert.
# NOTE: cannot assert with `gst-inspect cudaconvertscale` here — the nvcodec cuda*
# elements only register when a CUDA device is present, and `docker build` has no GPU.
# Verified at runtime instead (entrypoint / rtsp_capture available() check).
RUN NVRTC=$(ldconfig -p | awk '/libnvrtc\.so\.12/{print $NF; exit}') \
    && ln -sf "$NVRTC" "$(dirname "$NVRTC")/libnvrtc.so" \
    && echo "$(dirname "$NVRTC")" > /etc/ld.so.conf.d/cuda-nvrtc.conf \
    && ldconfig \
    && test -e "$(dirname "$NVRTC")/libnvrtc.so" \
    && echo "OK libnvrtc.so symlink created"

# Set python3.12 as default and bootstrap pip
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 \
    && curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12 \
    && pip install --upgrade pip setuptools wheel

WORKDIR /app

COPY requirements.txt requirements-paddle-gpu.txt ./

# Step 1: PaddlePaddle GPU (cu129 wheel, paddle 3.3.1 — paddleocr>=3.3 cần paddle 3.x).
# cu129 chứ không phải cu126: build cu126 KHÔNG có kernel cho sm_120 (RTX 50xx/Blackwell),
# suy luận GPU trả rỗng âm thầm -> OCR không đọc được biển số.
RUN pip install -r requirements-paddle-gpu.txt

# Step 2: PyTorch GPU (cu128 — bắt buộc cho sm_120 / RTX 50xx; cu126 trở xuống không có kernel)
RUN pip install torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu128

# Step 2b: paddle cu129 ghim nvidia-nccl-cu12==2.27.3 / cudnn 9.9.0.52 (CUDA 12.9),
# nhung torch 2.11.0+cu128 can nccl 2.28.9 / cudnn 9.19.0.56 — thieu se loi
# 'undefined symbol: ncclDevCommCreate'. Ghim lai dung ban cho torch.
RUN pip install "nvidia-nccl-cu12==2.28.9" "nvidia-cudnn-cu12==9.19.0.56"

# Step 3: FastAPI server deps + các thư viện AI còn lại.
# Hai pin trong requirements.txt không cài được trên Python 3.12 (đã báo lại để sửa ở repo):
#   1. `onnx==1.23.0` cần protobuf>=6.31.1, xung đột `protobuf==3.20.2` mà paddle/paddleocr cần
#      (server lúc chạy chỉ dùng onnxruntime; onnx chỉ cho scripts/export_engines.py).
#   2. `opencv-contrib-python==4.6.0.66` KHÔNG có wheel cho cp312 và xung đột paddlex[ocr-core]
#      -> dùng 4.10.0.84 (có wheel cp312 abi3, đã kiểm chứng chạy được với paddle 3.3/paddlex).
RUN grep -vE '^(onnx|opencv-contrib-python)==' requirements.txt > /tmp/req-fixed.txt \
    && pip install -r /tmp/req-fixed.txt "opencv-contrib-python==4.10.0.84" \
    && pip install --no-deps onnx==1.23.0

# Step 4: TensorRT cho model .engine (Ultralytics TRT + app/services/ai/trt_engine.py).
# Wheel cu12 mang sẵn libnvinfer/libnvonnxparser trong tensorrt_libs/ — app/utils/ai/gpu_bootstrap.py
# tạo symlink tên không version cho Paddle dlopen. Version >=10,<11 đúng như repo yêu cầu.
RUN pip install "tensorrt-cu12>=10,<11"

# Step 5: symlink TÊN KHÔNG VERSION cho TensorRT ở tầng hệ thống. Paddle dlopen đúng
# 'libnvinfer.so' / 'libnvonnxparser.so' còn wheel chỉ có '.so.10'. (app/utils/ai/gpu_bootstrap.py
# cũng tạo symlink trong app/runtime-media/cuda-libs, nhưng thư mục đó nằm trong repo và có thể
# mang theo symlink hỏng của máy khác -> làm sẵn ở image để chắc chắn.)
RUN TRT_LIBS="$(python -c 'import tensorrt_libs, os; print(os.path.dirname(tensorrt_libs.__file__))')" \
    && for stem in libnvinfer libnvinfer_plugin libnvonnxparser; do \
         target="$(ls "$TRT_LIBS"/${stem}.so.* 2>/dev/null | sort -V | tail -1)"; \
         if [ -n "$target" ]; then ln -sf "$target" /usr/local/lib/${stem}.so; fi; \
       done \
    && echo "$TRT_LIBS" > /etc/ld.so.conf.d/tensorrt.conf \
    && ldconfig \
    && LD_LIBRARY_PATH="$TRT_LIBS:$LD_LIBRARY_PATH" python -c "import ctypes; [ctypes.CDLL(n) for n in ('libnvinfer.so','libnvonnxparser.so','libnvinfer_builder_resource_sm120.so.10.16.1')]; print('OK: TRT libs tìm thấy được (kể cả builder_resource_sm120)')"


COPY . .

EXPOSE 8080

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Thư mục TRT libs phải có trên LD_LIBRARY_PATH: paddle dlopen
# 'libnvinfer_builder_resource_sm120.so.10.16.1' theo TÊN (ldconfig một mình không đủ) khi build
# engine TRT cho PaddleOCR (run_mode=trt_fp16). Khai báo ở cuối file để giữ cache layer nặng.
ENV LD_LIBRARY_PATH=/usr/local/lib/python3.12/dist-packages/tensorrt_libs:/usr/local/nvidia/lib:/usr/local/nvidia/lib64

ENTRYPOINT ["/entrypoint.sh"]
